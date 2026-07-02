import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/formatters.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/portal_providers.dart';
import '../../services/services.dart';
import '../../widgets/form/form_widgets.dart';
import '../../widgets/polish/polish.dart';

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
  final _guardianEmailController = TextEditingController();
  final _guardianCpfController = TextEditingController();
  String _guardianRelationship = '';
  final _tuitionValueController = TextEditingController();
  final _tuitionDayController = TextEditingController();
  final _monthlyGoalController = TextEditingController(); // A4 override (vazio = padrão)
  final _healthNotesController = TextEditingController();
  final _allergiesController = TextEditingController();
  // Body-composition goal (optional)
  final _targetWeightController = TextEditingController();
  final _targetBodyFatController = TextEditingController();

  // Form values
  DateTime? _birthDate;
  Sex? _sex;
  DateTime _startDate = DateTime.now();
  StudentCategory _category = StudentCategory.adult;
  StudentStatus _status = StudentStatus.active;
  List<Plan> _selectedPlans = [];
  List<Plan> _availablePlans = [];

  // Multi-sport graduation state. Each entry holds the current belt+stripes
  // for one modality the student practices. Starts empty so that creating a
  // new student forces the admin to consciously pick at least one modality
  // (BJJ is no longer assumed). When editing, the map is hydrated from the
  // student's sportsList in `_loadStudentData`.
  final Map<SportId, ({String belt, int stripes})> _grades = {};
  SportId? _primarySport;

  // Which Muay Thai grade ladder to offer (academy default, or the one that
  // matches an existing student's stored grade). See [resolveMuaythaiVariant].
  String _muaythaiVariant = muaythaiVariantCbmt;

  // Error tracking per tab
  final Map<String, bool> _tabErrors = {
    'personal': false,
    'contact': false,
    'academy': false,
  };

  bool get isEditing => widget.studentId != null;

  // Calculate form progress
  double get _formProgress {
    int filled = 0;
    int total = 1; // Only full name is required

    if (_fullNameController.text.isNotEmpty) filled++;

    // Optional but valuable fields
    total += 9;
    if (_grades[_primarySport]?.belt.isNotEmpty ?? false) filled++;
    if (_phoneController.text.isNotEmpty) filled++;
    if (_emailController.text.isNotEmpty) filled++;
    if (_birthDate != null) filled++;
    if (_emergencyContactNameController.text.isNotEmpty) filled++;
    if (_selectedPlans.isNotEmpty) filled++;
    if (_nicknameController.text.isNotEmpty) filled++;
    if (_tuitionValueController.text.isNotEmpty) filled++;
    if (_tuitionDayController.text.isNotEmpty) filled++;

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
  ];

  @override
  void initState() {
    super.initState();
    // Listen to name changes to update save button visibility
    _fullNameController.addListener(() {
      setState(() {}); // Rebuild to show/hide save button
    });
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
    _guardianEmailController.dispose();
    _guardianCpfController.dispose();
    _tuitionValueController.dispose();
    _tuitionDayController.dispose();
    _monthlyGoalController.dispose();
    _healthNotesController.dispose();
    _allergiesController.dispose();
    _targetWeightController.dispose();
    _targetBodyFatController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final academyId = FirebaseService.academyId;
      final planService = PlanService(academyId);

      _availablePlans = await planService.list();

      // Academy's default Muay Thai ladder (overridden per-student below when
      // editing someone who already has a grade from the other system). Await
      // the future so a brand-new student lands on the right ladder even if the
      // settings provider hasn't resolved yet.
      final settings = await ref.read(academySettingsProvider.future);
      _muaythaiVariant = settings?.muaythaiGradeSystem ?? muaythaiVariantCbmt;

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
    _phoneController.text = formatPhone(student.phone);
    _cpfController.text = formatCpfCnpj(student.cpf);
    _emergencyContactNameController.text = student.emergencyContact?.name ?? '';
    _emergencyContactPhoneController.text =
        formatPhone(student.emergencyContact?.phone);
    _guardianNameController.text = student.guardian?.name ?? '';
    _guardianPhoneController.text = formatPhone(student.guardian?.phone);
    _guardianEmailController.text = student.guardian?.email ?? '';
    _guardianCpfController.text = formatCpfCnpj(student.guardian?.cpf);
    _guardianRelationship = student.guardian?.relationship ?? '';
    _tuitionValueController.text = student.tuitionValue.toStringAsFixed(2).replaceAll('.', ',');
    _tuitionDayController.text = student.tuitionDay.toString();
    _monthlyGoalController.text =
        (student.monthlyAttendanceGoal ?? 0) > 0
            ? student.monthlyAttendanceGoal.toString()
            : '';
    _healthNotesController.text = student.healthNotes ?? '';
    _targetWeightController.text = _numText(student.targetWeightKg);
    _targetBodyFatController.text = _numText(student.targetBodyFatPct);
    _birthDate = student.birthDate;
    _sex = student.sex;
    _startDate = student.startDate;
    _category = student.category;
    _status = student.status;

    // Hydrate per-sport grades from the student. Falls back to BJJ legacy
    // fields when sportsList/sportData are absent.
    _grades.clear();
    final sportList = student.getSports();
    for (final sport in sportList) {
      final grade = student.getGrade(sport);
      _grades[sport] = (
        belt: grade?.currentGrade ?? 'white',
        stripes: grade?.currentStripes ?? 0,
      );
    }
    if (_grades.isEmpty) {
      _grades[SportId.bjj] = (
        belt: student.currentBelt,
        stripes: student.currentStripes,
      );
    }
    // Match the Muay Thai ladder to the student's stored grade so the selector
    // shows their actual system even if the academy default differs. Skip the
    // shared/ambiguous starting 'white' (and empty) — it belongs to neither
    // ladder unambiguously, so resolving it would snap a CBMTT academy back to
    // CBMT; keep the academy default seeded above in that case.
    final mtGrade = _grades[SportId.muaythai]?.belt;
    if (mtGrade != null && mtGrade.isNotEmpty && mtGrade != 'white') {
      _muaythaiVariant = resolveMuaythaiVariant(mtGrade);
    }
    _primarySport = student.getPrimarySport();
    if (!_grades.containsKey(_primarySport)) {
      _primarySport = _grades.isEmpty ? null : _grades.keys.first;
    }

    _selectedPlans = _availablePlans
        .where((p) => p.studentIds.contains(student.id))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(),
      body: _isLoading
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: PolishSkeleton.list(count: 4, itemHeight: 96),
            )
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
                        child: KeyedSubtree(
                          key: const ValueKey('personal'),
                          child: _buildPersonalTab().fadeInQuick(),
                        ),
                      ),

                      // Contact Tab
                      FormTabPanel(
                        tabKey: 'contact',
                        activeTab: _activeTab,
                        child: KeyedSubtree(
                          key: const ValueKey('contact'),
                          child: _buildContactTab().fadeInQuick(),
                        ),
                      ),

                      // Academy Tab
                      FormTabPanel(
                        tabKey: 'academy',
                        activeTab: _activeTab,
                        child: KeyedSubtree(
                          key: const ValueKey('academy'),
                          child: _buildAcademyTab().fadeInQuick(),
                        ),
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
    // Check if required field (name) is filled to enable save button
    final canSave = _fullNameController.text.trim().isNotEmpty;
    final isLastTab = _activeTab == 'academy';

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
          // Back button (show on all tabs except first)
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

          // Next button (show on all tabs except last, IF name is filled)
          if (!isLastTab && canSave)
            Expanded(
              child: ElevatedButton.icon(
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

          // Next button alone when name not filled (only navigation, no save option)
          if (!isLastTab && !canSave)
            Expanded(
              child: ElevatedButton.icon(
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

          // Spacing between buttons when both are shown
          if (canSave && !isLastTab) const SizedBox(width: 12),

          // Save button (show when name is filled)
          if (canSave)
            Expanded(
              child: ElevatedButton.icon(
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
                label: Text(_isSaving ? 'Salvando...' : 'Salvar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
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
              const SizedBox(height: 16),
              FormRow(
                children: [
                  _buildSexDropdown(),
                  const SizedBox(),
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
                FormRow(
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
                    PhoneInput(
                      controller: _guardianPhoneController,
                      label: 'WhatsApp do Responsável',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FormRow(
                  children: [
                    EmailInput(
                      controller: _guardianEmailController,
                      label: 'E-mail do Responsável',
                    ),
                    CPFInput(
                      controller: _guardianCpfController,
                      label: 'CPF do Responsável',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildGuardianRelationshipDropdown(),
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
          if (value != null) {
            setState(() {
              _category = value;
              // Category change can swap kids ↔ adult grades. Reset each sport
              // to the first available grade so we never leave an orphan id.
              final categoryStr = value.value;
              for (final sport in _grades.keys.toList()) {
                final list = getGradesForSport(
                  sport,
                  category: categoryStr,
                  muaythaiVariant:
                      sport == SportId.muaythai ? _muaythaiVariant : null,
                );
                final firstId = list.isNotEmpty ? list.first.id : 'white';
                _grades[sport] = (belt: firstId, stripes: 0);
              }
            });
          }
        },
        dropdownColor: AppTheme.surface,
      ),
    );
  }

  /// Formats an optional number for a text field (pt-BR comma, trims `.0`).
  static String _numText(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble()
        ? v.toInt().toString()
        : v.toString().replaceAll('.', ',');
  }

  /// Parses a pt-BR/EN decimal from a text field. Empty/invalid → null.
  double? _parseNum(String t) {
    final s = t.trim().replaceAll(',', '.');
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  Widget _buildSexDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: DropdownButtonFormField<Sex?>(
        value: _sex,
        isExpanded: true,
        icon: Icon(LucideIcons.chevronDown,
            color: AppTheme.textSecondary, size: 20),
        decoration: InputDecoration(
          labelText: 'Sexo (opcional)',
          prefixIcon:
              Icon(LucideIcons.userCheck, size: 20, color: AppTheme.textSecondary),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        items: [
          DropdownMenuItem<Sex?>(
            value: null,
            child: Text('Não informado', style: AppTheme.bodyMedium),
          ),
          ...Sex.values.map((s) => DropdownMenuItem<Sex?>(
                value: s,
                child: Text(s.label, style: AppTheme.bodyMedium),
              )),
        ],
        onChanged: (value) => setState(() => _sex = value),
        dropdownColor: AppTheme.surface,
      ),
    );
  }

  Widget _buildGuardianRelationshipDropdown() {
    const options = ['Pai', 'Mãe', 'Avô/Avó', 'Tio/Tia', 'Outro'];
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: DropdownButtonFormField<String>(
        value: _guardianRelationship.isEmpty ? null : _guardianRelationship,
        isExpanded: true,
        icon: Icon(LucideIcons.chevronDown, color: AppTheme.textSecondary, size: 20),
        decoration: InputDecoration(
          labelText: 'Parentesco',
          prefixIcon: Icon(LucideIcons.users, size: 20, color: AppTheme.textSecondary),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        items: options.map((rel) {
          return DropdownMenuItem(
            value: rel,
            child: Text(rel, style: AppTheme.bodyMedium),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null) setState(() => _guardianRelationship = value);
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
          subtitle: 'Modalidades, faixas e graus atuais',
          icon: LucideIcons.medal,
          child: _buildGraduationEditor(),
        ),

        const SizedBox(height: 16),

        // Financial Section (Optional)
        FormSection(
          title: 'Financeiro (Opcional)',
          subtitle: 'Planos e mensalidade',
          icon: LucideIcons.wallet,
          collapsible: true,
          defaultCollapsed: true,
          child: Column(
            children: [
              _buildPlanDropdown(),
              const SizedBox(height: 16),
              FormRow(
                children: [
                  CurrencyInput(
                    controller: _tuitionValueController,
                    label: 'Valor da Mensalidade (Opcional)',
                  ),
                  InputField(
                    controller: _tuitionDayController,
                    label: 'Dia de Vencimento',
                    hintText: '1-31 (Opcional)',
                    prefixIcon: LucideIcons.calendar,
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value?.isNotEmpty == true) {
                        final day = int.tryParse(value!);
                        if (day == null || day < 1 || day > 31) {
                          return 'Dia inválido (1-31)';
                        }
                      }
                      return null;
                    },
                    helperText: 'Em meses curtos, ajusta para o último dia',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              InputField(
                controller: _monthlyGoalController,
                label: 'Meta de frequência mensal (Opcional)',
                hintText: 'Vazio = padrão da academia',
                prefixIcon: LucideIcons.target,
                keyboardType: TextInputType.number,
                helperText:
                    'Sobrescreve a meta padrão da academia só para este aluno',
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

        FormSection(
          title: 'Meta / Objetivo',
          subtitle: 'Metas de composição corporal (mostradas na evolução)',
          icon: LucideIcons.target,
          badge: 'Opcional',
          collapsible: true,
          defaultCollapsed: _targetWeightController.text.isEmpty &&
              _targetBodyFatController.text.isEmpty,
          child: FormRow(
            children: [
              InputField(
                controller: _targetWeightController,
                label: 'Peso-alvo (kg)',
                hintText: 'Ex.: 78',
                prefixIcon: LucideIcons.scale,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              InputField(
                controller: _targetBodyFatController,
                label: '% Gordura-alvo',
                hintText: 'Ex.: 15',
                prefixIcon: LucideIcons.percent,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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
      case StudentStatus.transferred:
        return AppTheme.info;
    }
  }

  Widget _buildGraduationEditor() {
    final usedSports = _grades.keys.toList();
    final availableToAdd =
        sportOptions.where((s) => !_grades.containsKey(s)).toList();
    final hasError = _tabErrors['academy'] == true && _grades.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_grades.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: hasError
                  ? AppTheme.error.withValues(alpha: 0.08)
                  : AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasError ? AppTheme.error : AppTheme.divider,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasError ? LucideIcons.alertCircle : LucideIcons.medal,
                  color: hasError ? AppTheme.error : AppTheme.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hasError
                            ? 'Modalidade é obrigatória'
                            : 'Nenhuma modalidade selecionada',
                        style: AppTheme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: hasError
                              ? AppTheme.error
                              : AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'Adicione pelo menos uma modalidade para definir as faixas do aluno.',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final sport in usedSports) ...[
          _buildSportGradeBlock(sport),
          const SizedBox(height: 12),
        ],
        if (availableToAdd.isNotEmpty)
          _buildAddSportButton(availableToAdd),
      ],
    );
  }

  Widget _buildSportGradeBlock(SportId sport) {
    final sportDef = sports[sport]!;
    final accent = sportChipColors[sport] ?? AppTheme.primary;
    final isPrimary = _primarySport == sport;
    final isOnlySport = _grades.length == 1;
    final hasGradeSystem = sportDef.gradeSystem != GradeSystem.none;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPrimary ? accent : AppTheme.divider,
          width: isPrimary ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(sportDef.icon, color: accent, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          sportDef.label,
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (isPrimary)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'PRINCIPAL',
                              style: AppTheme.labelSmall.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (!hasGradeSystem)
                      Text(
                        'Sem sistema de graduação',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (!isPrimary)
                IconButton(
                  tooltip: 'Definir como principal',
                  icon: Icon(LucideIcons.star,
                      size: 18, color: AppTheme.textSecondary),
                  onPressed: () => setState(() => _primarySport = sport),
                ),
              if (!isOnlySport)
                IconButton(
                  tooltip: 'Remover modalidade',
                  icon: Icon(LucideIcons.x, size: 18, color: AppTheme.error),
                  onPressed: () => _removeSport(sport),
                ),
            ],
          ),
          if (hasGradeSystem) ...[
            const SizedBox(height: 10),
            FormRow(
              children: [
                _buildBeltSelectorForSport(sport),
                _buildStripesSelectorForSport(sport),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _removeSport(SportId sport) {
    if (_grades.length <= 1) return;
    setState(() {
      _grades.remove(sport);
      if (_primarySport == sport) {
        _primarySport = _grades.isEmpty ? null : _grades.keys.first;
      }
    });
  }

  Widget _buildAddSportButton(List<SportId> available) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showAddSportSheet(available),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.divider,
              style: BorderStyle.solid,
            ),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.plus, size: 18, color: AppTheme.textPrimary),
              const SizedBox(width: 8),
              Text(
                'Adicionar modalidade',
                style: AppTheme.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddSportSheet(List<SportId> available) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      // Allow the sheet to grow past the default ~half-screen so the modality
      // list can scroll instead of being clipped when there are many sports.
      isScrollControlled: true,
      builder: (sheetCtx) {
        final media = MediaQuery.of(sheetCtx);
        return Container(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.8),
          padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + media.viewPadding.bottom),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Adicionar modalidade',
                style:
                    AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              // Scrollable so every modality is reachable on small screens.
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: available.map((sport) {
                    final def = sports[sport]!;
                    final accent = sportChipColors[sport] ?? AppTheme.primary;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(def.icon, color: accent, size: 18),
                      ),
                      title: Text(def.label,
                          style: AppTheme.bodyMedium
                              .copyWith(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        def.gradeSystem == GradeSystem.none
                            ? 'Sem graduação'
                            : 'Faixas iniciam em ${getGradesForSport(sport, category: _category.value, muaythaiVariant: sport == SportId.muaythai ? _muaythaiVariant : null).firstOrNull?.label ?? '-'}',
                        style: AppTheme.labelSmall
                            .copyWith(color: AppTheme.textSecondary),
                      ),
                      onTap: () {
                        final grades = getGradesForSport(
                          sport,
                          category: _category.value,
                          muaythaiVariant: sport == SportId.muaythai
                              ? _muaythaiVariant
                              : null,
                        );
                        final firstId =
                            grades.isNotEmpty ? grades.first.id : 'white';
                        setState(() {
                          _grades[sport] = (belt: firstId, stripes: 0);
                          // First sport added → becomes the primary by default.
                          _primarySport ??= sport;
                          _tabErrors['academy'] = false;
                        });
                        Navigator.pop(sheetCtx);
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBeltSelectorForSport(SportId sport) {
    final grades = getGradesForSport(
      sport,
      category: _category.value,
      muaythaiVariant: sport == SportId.muaythai ? _muaythaiVariant : null,
    );
    if (grades.isEmpty) {
      return const SizedBox.shrink();
    }
    final gradeIds = grades.map((g) => g.id).toList();
    final current = _grades[sport]!;
    final value =
        gradeIds.contains(current.belt) ? current.belt : grades.first.id;

    final beltDropdown = Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        icon: Icon(LucideIcons.chevronDown,
            color: AppTheme.textSecondary, size: 20),
        decoration: InputDecoration(
          labelText: 'Faixa',
          prefixIcon:
              Icon(LucideIcons.award, size: 20, color: AppTheme.textSecondary),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                            color: isWhiteStripe ? Colors.white : Colors.black,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(grade.label, style: AppTheme.bodyMedium),
              ],
            ),
          );
        }).toList(),
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            _grades[sport] = (belt: v, stripes: _grades[sport]!.stripes);
          });
        },
        dropdownColor: AppTheme.surface,
      ),
    );

    // Muay Thai has two graduation ladders; let the admin switch this student's
    // system. Switching resets the grade to the new ladder's first rank
    // (Branca) — the two systems don't map 1:1, so we never auto-convert.
    if (sport != SportId.muaythai) return beltDropdown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMuaythaiSystemSelector(),
        const SizedBox(height: 8),
        beltDropdown,
      ],
    );
  }

  Widget _buildMuaythaiSystemSelector() {
    Widget chip(String variant, String label) {
      final selected = _muaythaiVariant == variant;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: selected
              ? null
              : () => setState(() {
                    _muaythaiVariant = variant;
                    // Trocar e reiniciar: volta ao primeiro grau do sistema novo.
                    final first = getGradesForSport(
                      SportId.muaythai,
                      muaythaiVariant: variant,
                    ).first.id;
                    _grades[SportId.muaythai] = (belt: first, stripes: 0);
                  }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.08)
                  : AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? AppTheme.primary : AppTheme.divider,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTheme.labelSmall.copyWith(
                color: selected ? AppTheme.primary : AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sistema de graduacao',
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            chip(muaythaiVariantCbmt, 'CBMT / CMTB'),
            const SizedBox(width: 8),
            chip(muaythaiVariantCbmtt, 'CBMT Tradicional'),
          ],
        ),
      ],
    );
  }

  Widget _buildStripesSelectorForSport(SportId sport) {
    final sportDef = sports[sport]!;
    if (!sportDef.supportsStripes) {
      return const SizedBox.shrink();
    }
    final entry = _grades[sport]!;
    final gradeDef = getGradeDefinition(sport, entry.belt);
    final maxStripes = gradeDef?.maxStripes ?? 4;
    final clampedStripes = entry.stripes > maxStripes ? 0 : entry.stripes;
    if (entry.stripes > maxStripes) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _grades[sport] = (belt: entry.belt, stripes: 0);
        });
      });
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: DropdownButtonFormField<int>(
        value: clampedStripes,
        isExpanded: true,
        icon: Icon(LucideIcons.chevronDown,
            color: AppTheme.textSecondary, size: 20),
        decoration: InputDecoration(
          labelText: 'Graus',
          prefixIcon:
              Icon(LucideIcons.hash, size: 20, color: AppTheme.textSecondary),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        items: List.generate(maxStripes + 1, (i) {
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
                Text('$i grau${i != 1 ? 's' : ''}',
                    style: AppTheme.bodyMedium),
              ],
            ),
          );
        }).toList(),
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            _grades[sport] = (belt: entry.belt, stripes: v);
          });
        },
        dropdownColor: AppTheme.surface,
      ),
    );
  }



  Widget _buildPlanDropdown() {
    final selectedIds = _selectedPlans.map((p) => p.id).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.package, size: 20, color: AppTheme.textSecondary),
            const SizedBox(width: 8),
            Text('Planos', style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _availablePlans.map((plan) {
            final isSelected = selectedIds.contains(plan.id);
            return FilterChip(
              label: Text(
                '${plan.name} - R\$ ${plan.monthlyValue.toStringAsFixed(2).replaceAll('.', ',')}',
              ),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedPlans.add(plan);
                  } else {
                    _selectedPlans.removeWhere((p) => p.id == plan.id);
                  }
                });
              },
              selectedColor: AppTheme.primary.withValues(alpha: 0.15),
              checkmarkColor: AppTheme.primary,
              backgroundColor: AppTheme.surface,
              side: BorderSide(
                color: isSelected ? AppTheme.primary : AppTheme.divider,
              ),
              labelStyle: AppTheme.bodyMedium.copyWith(
                color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
              ),
            );
          }).toList(),
        ),
        if (_selectedPlans.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Nenhum plano selecionado (Projeto Social)',
              style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
            ),
          ),
      ],
    );
  }

  // ============================================
  // SAVE STUDENT
  // ============================================
  Future<void> _saveStudent() async {
    final isFormValid = _formKey.currentState!.validate();
    final hasNoSport = _grades.isEmpty;

    if (!isFormValid || hasNoSport) {
      _updateTabErrors();
      final errorTab = _tabErrors.entries.firstWhere(
        (e) => e.value,
        orElse: () => MapEntry('personal', false),
      );
      if (errorTab.value) {
        setState(() => _activeTab = errorTab.key);
      }
      context.showError(
        hasNoSport
            ? 'Selecione pelo menos uma modalidade'
            : 'Corrija os erros no formulário',
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final academyId = FirebaseService.academyId;
      final studentService = StudentService(academyId);

      final primarySport = _primarySport ?? _grades.keys.first;
      final primaryGrade = _grades[primarySport]!;
      final sportData = <String, dynamic>{};
      for (final entry in _grades.entries) {
        sportData[entry.key.value] = {
          'currentGrade': entry.value.belt,
          'currentStripes': entry.value.stripes,
        };
      }

      final data = <String, dynamic>{
        'fullName': _fullNameController.text.trim(),
        'nickname': _nicknameController.text.trim().isEmpty ? null : _nicknameController.text.trim(),
        'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : onlyDigits(_phoneController.text),
        'cpf': _cpfController.text.trim().isEmpty
            ? null
            : onlyDigits(_cpfController.text),
        'birthDate': _birthDate != null ? Timestamp.fromDate(_birthDate!) : null,
        'sex': _sex?.value,
        'targetWeightKg': _parseNum(_targetWeightController.text),
        'targetBodyFatPct': _parseNum(_targetBodyFatController.text),
        'category': _category.value,
        'startDate': Timestamp.fromDate(_startDate),
        // Legacy fields — kept synced to the primary sport so single-sport
        // (BJJ) reads in older code paths still work.
        'currentBelt': primaryGrade.belt,
        'currentStripes': primaryGrade.stripes,
        // Multi-sport fields. `sports` is the modality list, `sportData` holds
        // grade+stripes per sport, `primarySport` is the displayed default.
        'sports': _grades.keys.map((s) => s.value).toList(),
        'sportData': sportData,
        'primarySport': primarySport.value,
        'status': _status.value,
        'tuitionValue': _tuitionValueController.text.trim().isEmpty 
            ? 0.0 
            : double.tryParse(_tuitionValueController.text.replaceAll(',', '.')) ?? 0.0,
        'tuitionDay': _tuitionDayController.text.trim().isEmpty 
            ? 10 
            : int.tryParse(_tuitionDayController.text) ?? 10,
        'healthNotes': _healthNotesController.text.trim().isEmpty ? null : _healthNotesController.text.trim(),
        // A4: per-student monthly attendance goal override (empty/0 = use the
        // academy default).
        'monthlyAttendanceGoal':
            int.tryParse(_monthlyGoalController.text.trim()),
      };

      // Emergency contact
      if (_emergencyContactNameController.text.isNotEmpty) {
        data['emergencyContact'] = {
          'name': _emergencyContactNameController.text.trim(),
          'phone': onlyDigits(_emergencyContactPhoneController.text),
          'relationship': 'Emergência',
        };
      }

      // Guardian (for kids)
      if (_category == StudentCategory.kids && _guardianNameController.text.isNotEmpty) {
        data['guardian'] = {
          'name': _guardianNameController.text.trim(),
          'phone': onlyDigits(_guardianPhoneController.text),
          'email': _guardianEmailController.text.trim().isEmpty ? null : _guardianEmailController.text.trim(),
          'cpf': _guardianCpfController.text.trim().isEmpty ? null : onlyDigits(_guardianCpfController.text),
          'relationship': _guardianRelationship.isEmpty ? 'Outro' : _guardianRelationship,
        };
      }

      String studentId;
      if (isEditing) {
        await studentService.update(widget.studentId!, data);
        studentId = widget.studentId!;
      } else {
        data['isProfilePublic'] = true;
        data['attendanceCount'] = 0;
        data['initialAttendanceCount'] = 0;
        final created = await studentService.createFromMap(data);
        studentId = created.id;
      }

      // Sync plans: add/remove student from plans as needed
      try {
        final planService = PlanService(academyId);
        final selectedPlanIds = _selectedPlans.map((p) => p.id).toSet();
        final currentPlanIds = _availablePlans
            .where((p) => p.studentIds.contains(studentId))
            .map((p) => p.id)
            .toSet();

        // Add to newly selected plans
        for (final planId in selectedPlanIds.difference(currentPlanIds)) {
          await planService.addStudent(planId, studentId);
        }
        // Remove from deselected plans
        for (final planId in currentPlanIds.difference(selectedPlanIds)) {
          await planService.removeStudent(planId, studentId);
        }
      } catch (planError) {
        debugPrint('Warning: Failed to sync plans: $planError');
        // Continue execution - student was created successfully
      }

      if (mounted) {
        context.showSuccess(isEditing ? 'Aluno atualizado!' : 'Aluno cadastrado!');
        if (isEditing) {
          // Return `true` so the detail screen's `context.push(...)` receives a
          // result and knows to call `_loadData()` with fresh Firestore data.
          context.pop(true);
        } else {
          // Genuine win — a new student joined the academy.
          Celebration.confetti(context);
          context.go('/admin/alunos');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _updateTabErrors() {
    _tabErrors['personal'] = _fullNameController.text.isEmpty ||
        (_category == StudentCategory.kids && _guardianNameController.text.isEmpty);
    _tabErrors['academy'] = _grades.isEmpty;
  }
}
