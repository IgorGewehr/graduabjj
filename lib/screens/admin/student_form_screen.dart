import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/domain_providers.dart' as tatami;
import '../../api/dto/student_dto.dart' as api_student;
import '../../api/repositories.dart' as tatami_repos;
import '../../core/feedback_utils.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../services/services.dart';
import '../../widgets/form/form_widgets.dart';
import 'student_form/academy_tab.dart';
import 'student_form/contact_tab.dart';
import 'student_form/form_bottom_bar.dart';
import 'student_form/personal_tab.dart';

/// Admin Student Form Screen - Modern tabbed form with progress tracking
class AdminStudentFormScreen extends ConsumerStatefulWidget {
  final String? studentId;

  const AdminStudentFormScreen({super.key, this.studentId});

  @override
  ConsumerState<AdminStudentFormScreen> createState() =>
      _AdminStudentFormScreenState();
}

class _AdminStudentFormScreenState
    extends ConsumerState<AdminStudentFormScreen> {
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
  final _healthNotesController = TextEditingController();
  final _allergiesController = TextEditingController();

  // Form values
  DateTime? _birthDate;
  DateTime _startDate = DateTime.now();
  StudentCategory _category = StudentCategory.adult;
  StudentStatus _status = StudentStatus.active;
  List<Plan> _selectedPlans = [];
  List<Plan> _availablePlans = [];

  final Map<SportId, ({String belt, int stripes})> _grades = {};
  SportId? _primarySport;

  final Map<String, bool> _tabErrors = {
    'personal': false,
    'contact': false,
    'academy': false,
  };

  bool get isEditing => widget.studentId != null;

  double get _formProgress {
    int filled = 0;
    int total = 1;
    if (_fullNameController.text.isNotEmpty) filled++;
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
    _fullNameController.addListener(() => setState(() {}));
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
        try {
          final student = await ref.read(
            tatami.tatamiStudentByIdLegacyProvider(
              tatami.studentRef(academyId, widget.studentId!),
            ).future,
          );
          _existingStudent = student;
          _populateForm(student);
        } catch (_) {}
      }
    } catch (e) {
      // ignore
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
    _emergencyContactPhoneController.text =
        student.emergencyContact?.phone ?? '';
    _guardianNameController.text = student.guardian?.name ?? '';
    _guardianPhoneController.text = student.guardian?.phone ?? '';
    _guardianEmailController.text = student.guardian?.email ?? '';
    _guardianCpfController.text = student.guardian?.cpf ?? '';
    _guardianRelationship = student.guardian?.relationship ?? '';
    _tuitionValueController.text =
        student.tuitionValue.toStringAsFixed(2).replaceAll('.', ',');
    _tuitionDayController.text = student.tuitionDay.toString();
    _healthNotesController.text = student.healthNotes ?? '';
    _birthDate = student.birthDate;
    _startDate = student.startDate;
    _category = student.category;
    _status = student.status;

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
      appBar: AppBar(
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
                style:
                    AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
              ),
          ],
        ),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.divider),
        ),
      ),
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
                      FormTabPanel(
                        tabKey: 'personal',
                        activeTab: _activeTab,
                        child: _buildPersonalTab(),
                      ),
                      FormTabPanel(
                        tabKey: 'contact',
                        activeTab: _activeTab,
                        child: _buildContactTab(),
                      ),
                      FormTabPanel(
                        tabKey: 'academy',
                        activeTab: _activeTab,
                        child: _buildAcademyTab(),
                      ),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ),
      bottomNavigationBar: StudentFormBottomBar(
        activeTab: _activeTab,
        canSave: _fullNameController.text.trim().isNotEmpty,
        isSaving: _isSaving,
        onPrevious: _goToPreviousTab,
        onNext: _goToNextTab,
        onSave: _saveStudent,
      ),
    );
  }

  Widget _buildPersonalTab() {
    return PersonalTab(
      fullNameController: _fullNameController,
      nicknameController: _nicknameController,
      cpfController: _cpfController,
      birthDate: _birthDate,
      category: _category,
      guardianNameController: _guardianNameController,
      guardianPhoneController: _guardianPhoneController,
      guardianEmailController: _guardianEmailController,
      guardianCpfController: _guardianCpfController,
      guardianRelationship: _guardianRelationship,
      onChanged: () => setState(() {}),
      onBirthDateChanged: (date) => setState(() => _birthDate = date),
      onCategoryChanged: (value) {
        if (value == null) return;
        setState(() {
          _category = value;
          final categoryStr = value.value;
          for (final sport in _grades.keys.toList()) {
            final list = getGradesForSport(sport, category: categoryStr);
            final firstId = list.isNotEmpty ? list.first.id : 'white';
            _grades[sport] = (belt: firstId, stripes: 0);
          }
        });
      },
      onGuardianRelationshipChanged: (value) {
        if (value != null) setState(() => _guardianRelationship = value);
      },
    );
  }

  Widget _buildContactTab() {
    return ContactTab(
      emailController: _emailController,
      phoneController: _phoneController,
      emergencyContactNameController: _emergencyContactNameController,
      emergencyContactPhoneController: _emergencyContactPhoneController,
      onChanged: () => setState(() {}),
    );
  }

  Widget _buildAcademyTab() {
    return AcademyTab(
      startDate: _startDate,
      status: _status,
      grades: _grades,
      primarySport: _primarySport,
      category: _category,
      hasGradesError: (_tabErrors['academy'] == true) && _grades.isEmpty,
      availablePlans: _availablePlans,
      selectedPlans: _selectedPlans,
      tuitionValueController: _tuitionValueController,
      tuitionDayController: _tuitionDayController,
      healthNotesController: _healthNotesController,
      allergiesController: _allergiesController,
      onStartDateChanged: (date) {
        if (date != null) setState(() => _startDate = date);
      },
      onStatusChanged: (value) {
        if (value != null) setState(() => _status = value);
      },
      onSetPrimary: (sport) => setState(() => _primarySport = sport),
      onRemoveSport: (sport) {
        if (_grades.length <= 1) return;
        setState(() {
          _grades.remove(sport);
          if (_primarySport == sport) {
            _primarySport = _grades.isEmpty ? null : _grades.keys.first;
          }
        });
      },
      onAddSport: (sport) {
        final grades = getGradesForSport(sport, category: _category.value);
        final firstId = grades.isNotEmpty ? grades.first.id : 'white';
        setState(() {
          _grades[sport] = (belt: firstId, stripes: 0);
          _primarySport ??= sport;
          _tabErrors['academy'] = false;
        });
      },
      onGradeChanged: (sport, belt, stripes) {
        setState(() => _grades[sport] = (belt: belt, stripes: stripes));
      },
      onPlanToggle: (plan, selected) {
        setState(() {
          if (selected) {
            _selectedPlans.add(plan);
          } else {
            _selectedPlans.removeWhere((p) => p.id == plan.id);
          }
        });
      },
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

  void _updateTabErrors() {
    _tabErrors['personal'] = _fullNameController.text.isEmpty ||
        (_category == StudentCategory.kids &&
            _guardianNameController.text.isEmpty);
    _tabErrors['academy'] = _grades.isEmpty;
  }

  Future<void> _saveStudent() async {
    final isFormValid = _formKey.currentState!.validate();
    final hasNoSport = _grades.isEmpty;

    if (!isFormValid || hasNoSport) {
      _updateTabErrors();
      final errorTab = _tabErrors.entries.firstWhere(
        (e) => e.value,
        orElse: () => MapEntry('personal', false),
      );
      if (errorTab.value) setState(() => _activeTab = errorTab.key);
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
      final primarySport = _primarySport ?? _grades.keys.first;
      final primaryGrade = _grades[primarySport]!;
      final sportData = <String, dynamic>{};
      for (final entry in _grades.entries) {
        sportData[entry.key.value] = {
          'currentGrade': entry.value.belt,
          'currentStripes': entry.value.stripes,
        };
      }

      api_student.ApiGuardian? guardianDto;
      if (_category == StudentCategory.kids &&
          _guardianNameController.text.isNotEmpty) {
        guardianDto = api_student.ApiGuardian(
          name: _guardianNameController.text.trim(),
          phone: _guardianPhoneController.text.trim(),
          email: _guardianEmailController.text.trim().isEmpty
              ? null
              : _guardianEmailController.text.trim(),
          cpf: _guardianCpfController.text.trim().isEmpty
              ? null
              : _guardianCpfController.text.trim(),
        );
      }

      String? emergencyContactStr;
      if (_emergencyContactNameController.text.isNotEmpty) {
        emergencyContactStr =
            '${_emergencyContactNameController.text.trim()} | ${_emergencyContactPhoneController.text.trim()}';
      }

      String studentId;
      final repo = ref.read(tatami_repos.studentRepoProvider);

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
            cpf: _cpfController.text.trim().isEmpty
                ? null
                : _cpfController.text.trim(),
            birthDate: _birthDate,
            startDate: _startDate,
            category: _category == StudentCategory.kids
                ? api_student.ApiStudentCategory.kids
                : api_student.ApiStudentCategory.adult,
            status: api_student.ApiStudentStatusX.fromWire(_status.value),
            tuitionValue: _tuitionValueController.text.trim().isEmpty
                ? null
                : _tuitionValueController.text.trim().replaceAll(',', '.'),
            tuitionDay: int.tryParse(_tuitionDayController.text),
            healthNotes: _healthNotesController.text.trim().isEmpty
                ? null
                : _healthNotesController.text.trim(),
            primarySport: primarySport.value,
            guardian: guardianDto,
            emergencyContact: emergencyContactStr,
          ),
        );
        studentId = widget.studentId!;
      } else {
        final created = await repo.create(
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
            cpf: _cpfController.text.trim().isEmpty
                ? null
                : _cpfController.text.trim(),
            birthDate: _birthDate,
            startDate: _startDate,
            category: _category == StudentCategory.kids
                ? api_student.ApiStudentCategory.kids
                : api_student.ApiStudentCategory.adult,
            currentBelt: api_student.ApiBeltX.fromWire(primaryGrade.belt),
            currentStripes: primaryGrade.stripes,
            tuitionValue: _tuitionValueController.text.trim().isEmpty
                ? null
                : _tuitionValueController.text.trim().replaceAll(',', '.'),
            tuitionDay: int.tryParse(_tuitionDayController.text),
            healthNotes: _healthNotesController.text.trim().isEmpty
                ? null
                : _healthNotesController.text.trim(),
            isProfilePublic: false,
            initialAttendanceCount: 0,
            primarySport: primarySport.value,
            sportsList: _grades.keys.map((s) => s.value).toList(),
            sportData: sportData,
            guardian: guardianDto,
            emergencyContact: emergencyContactStr,
          ),
        );
        studentId = created.id;
      }

      try {
        final planService = PlanService(academyId);
        final selectedPlanIds = _selectedPlans.map((p) => p.id).toSet();
        final currentPlanIds = _availablePlans
            .where((p) => p.studentIds.contains(studentId))
            .map((p) => p.id)
            .toSet();

        for (final planId in selectedPlanIds.difference(currentPlanIds)) {
          await planService.addStudent(planId, studentId);
        }
        for (final planId in currentPlanIds.difference(selectedPlanIds)) {
          await planService.removeStudent(planId, studentId);
        }
      } catch (planError) {
        debugPrint('Warning: Failed to sync plans: $planError');
      }

      if (mounted) {
        context.showSuccess(
          isEditing ? 'Aluno atualizado!' : 'Aluno cadastrado!',
        );
        context.go('/admin/alunos');
      }
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
