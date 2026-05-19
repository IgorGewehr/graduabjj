import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../api/dto/upload_dto.dart' as api_upload;
import '../../api/repositories.dart' as tatami_repos;
import '../../core/constants.dart';
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/portal_providers.dart';
import '../../services/services.dart';
import 'settings/academy_tab.dart';
import 'settings/features_tab.dart';
import 'settings/financial_tab.dart';
import 'settings/monitors_tab.dart';
import 'team_tab_content.dart';

/// Admin Settings Screen - Fintech style matching webapp
class AdminSettingsScreen extends ConsumerStatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  ConsumerState<AdminSettingsScreen> createState() =>
      _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends ConsumerState<AdminSettingsScreen> {
  AcademySettings? _settings;
  bool _isLoading = true;
  bool _isSaving = false;
  int _selectedTabIndex = 0;

  // Form controllers
  final _nameController = TextEditingController();
  final _sloganController = TextEditingController();
  final _cnpjController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _zipCodeController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _pixKeyController = TextEditingController();
  final _storeWelcomeController = TextEditingController();
  final _storeMinAmountController = TextEditingController();

  PixKeyType? _pixKeyType;
  bool _abacatePayEnabled = false;
  bool _asaasEnabled = false;
  bool _storeEnabled = false;
  bool _storePublished = false;
  bool _storeCreditCardEnabled = false;
  bool _studentCheckinEnabled = false;

  // Auto-graduation + class weights
  bool _autoGraduationEnabled = false;
  bool _useClassWeights = false;
  final _autoGraduationAttendancesController = TextEditingController(
    text: '70',
  );

  // Monitors
  List<String> _monitorIds = [];
  List<Map<String, dynamic>> _linkedStudents = [];
  bool _isLoadingMonitors = false;

  // KYC
  String _kycStatus = 'not_checked';
  String? _kycOnboardingUrl;
  bool _isCheckingKyc = false;

  final _tabs = [
    'Academia',
    'Financeiro',
    'Monitores',
    'Funcionalidades',
    'Equipe',
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sloganController.dispose();
    _cnpjController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipCodeController.dispose();
    _birthDateController.dispose();
    _pixKeyController.dispose();
    _storeWelcomeController.dispose();
    _storeMinAmountController.dispose();
    _autoGraduationAttendancesController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final service = SettingsService(FirebaseService.academyId);
      final settings = await service.getAcademySettings();

      if (settings != null) {
        setState(() {
          _settings = settings;
          _nameController.text = settings.name;
          _sloganController.text = settings.portalSlogan ?? '';
          _cnpjController.text = settings.cnpj ?? '';
          _emailController.text = settings.email ?? '';
          _phoneController.text = settings.phone ?? '';
          _addressController.text = settings.address ?? '';
          _cityController.text = settings.city ?? '';
          _stateController.text = settings.state ?? '';
          _zipCodeController.text = settings.zipCode ?? '';
          _birthDateController.text = settings.responsibleBirthDate ?? '';
          _pixKeyController.text = settings.pixKey ?? '';
          _storeWelcomeController.text = settings.storeWelcomeMessage ?? '';
          _storeMinAmountController.text =
              settings.storeMinOrderAmount?.toStringAsFixed(2) ?? '';
          _pixKeyType = settings.pixKeyType;
          _abacatePayEnabled = settings.abacatePayEnabled;
          _asaasEnabled = settings.asaasEnabled;
          _storeEnabled = settings.storeEnabled;
          _storePublished = settings.storePublished;
          _storeCreditCardEnabled = settings.storeCreditCardEnabled;
          _studentCheckinEnabled = settings.studentCheckinEnabled;
          _autoGraduationEnabled = settings.autoGraduationEnabled;
          _useClassWeights = settings.useClassWeights;
          if (settings.autoGraduationAttendances != null) {
            _autoGraduationAttendancesController.text = settings
                .autoGraduationAttendances
                .toString();
          }
          _monitorIds = settings.monitorIds;
        });
      }

      await _loadLinkedStudents();

      if (_asaasEnabled) {
        _checkKycStatus();
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadLinkedStudents() async {
    try {
      final studentService = StudentService(FirebaseService.academyId);
      final allStudents = await studentService.getAll();

      final linked = allStudents
          .where(
            (s) => s.linkedUserId != null && s.status == StudentStatus.active,
          )
          .map(
            (s) => {'id': s.id, 'fullName': s.fullName, 'nickname': s.nickname},
          )
          .toList();

      setState(() {
        _linkedStudents = linked;
      });
    } catch (e) {
      // Ignore errors
    }
  }

  Future<void> _addMonitor(String studentId) async {
    setState(() => _isLoadingMonitors = true);
    try {
      final service = SettingsService(FirebaseService.academyId);
      await service.addMonitor(studentId);
      setState(() {
        _monitorIds = [..._monitorIds, studentId];
      });
      ref.invalidate(academySettingsProvider);
      if (mounted) context.showSuccess('Monitor adicionado!');
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      setState(() => _isLoadingMonitors = false);
    }
  }

  Future<void> _removeMonitor(String studentId) async {
    setState(() => _isLoadingMonitors = true);
    try {
      final service = SettingsService(FirebaseService.academyId);
      await service.removeMonitor(studentId);
      setState(() {
        _monitorIds = _monitorIds.where((id) => id != studentId).toList();
      });
      ref.invalidate(academySettingsProvider);
      if (mounted) context.showSuccess('Monitor removido!');
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      setState(() => _isLoadingMonitors = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final service = SettingsService(FirebaseService.academyId);

      await service.updateBasicInfo(
        name: _nameController.text,
        cnpj: _cnpjController.text.isEmpty ? null : _cnpjController.text,
        email: _emailController.text.isEmpty ? null : _emailController.text,
        phone: _phoneController.text.isEmpty ? null : _phoneController.text,
        address: _addressController.text.isEmpty
            ? null
            : _addressController.text,
        city: _cityController.text.isEmpty ? null : _cityController.text,
        state: _stateController.text.isEmpty ? null : _stateController.text,
        zipCode: _zipCodeController.text.isEmpty
            ? null
            : _zipCodeController.text,
        responsibleBirthDate: _birthDateController.text.isEmpty
            ? null
            : _birthDateController.text,
      );

      if (_pixKeyController.text.isNotEmpty && _pixKeyType != null) {
        await service.updatePixInfo(_pixKeyController.text, _pixKeyType!);
      }

      await service.updateBranding(
        portalSlogan: _sloganController.text.isEmpty
            ? null
            : _sloganController.text,
      );

      await service.updateStoreSettings(
        enabled: _storeEnabled,
        published: _storePublished,
        creditCardEnabled: _storeCreditCardEnabled,
        welcomeMessage: _storeWelcomeController.text.isEmpty
            ? null
            : _storeWelcomeController.text,
        minOrderAmount: _storeMinAmountController.text.isNotEmpty
            ? double.tryParse(_storeMinAmountController.text)
            : null,
      );

      await service.toggleAbacatePay(_abacatePayEnabled);
      await service.toggleAsaas(_asaasEnabled);
      await service.toggleStudentCheckin(_studentCheckinEnabled);

      final attendancesValue = int.tryParse(
        _autoGraduationAttendancesController.text,
      );
      await service.updateAutoGraduation(
        _autoGraduationEnabled,
        attendances: attendancesValue,
      );
      await service.updateUseClassWeights(_useClassWeights);

      ref.invalidate(academySettingsProvider);
      ref.invalidate(academyNameProvider);
      ref.invalidate(pixInfoProvider);

      if (mounted) context.showSuccess('Configuracoes salvas!');
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final initial = _birthDateController.text.isNotEmpty
        ? DateTime.tryParse(_birthDateController.text) ?? DateTime(1990)
        : DateTime(1990);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: 'Data de Nascimento do Responsavel',
    );
    if (picked != null) {
      setState(() {
        _birthDateController.text =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _checkKycStatus() async {
    setState(() => _isCheckingKyc = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();

      final url = Uri.parse(
        '${AppConstants.apiBaseUrl}/payments/onboard/documents?academyId=${FirebaseService.academyId}',
      );
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        final data = body['data'] as Map<String, dynamic>;
        setState(() {
          _kycStatus = data['status'] as String? ?? 'not_checked';
          _kycOnboardingUrl = data['onboardingUrl'] as String?;
        });
      } else {
        if (mounted) {
          context.showError(
            body['error'] as String? ?? 'Erro ao verificar documentos',
          );
        }
      }
    } catch (e) {
      if (mounted) context.showError('Erro ao verificar documentos');
    } finally {
      setState(() => _isCheckingKyc = false);
    }
  }

  Future<void> _pickAndUploadLogo() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressQuality: 85,
        maxWidth: 512,
        maxHeight: 512,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Recortar Logo',
            toolbarColor: AppTheme.textPrimary,
            toolbarWidgetColor: Colors.white,
            statusBarColor: AppTheme.textPrimary,
            backgroundColor: AppTheme.background,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            hideBottomControls: true,
          ),
          IOSUiSettings(
            title: 'Recortar Logo',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            aspectRatioPickerButtonHidden: true,
          ),
        ],
      );

      if (croppedFile == null) return;

      setState(() => _isSaving = true);

      final academyId = FirebaseService.academyId;
      final file = File(croppedFile.path);

      final repo = ref.read(tatami_repos.uploadsRepoProvider);
      final uploaded = await repo.uploadFileFromDisk(
        purpose: api_upload.ApiUploadPurpose.academySettings,
        file: file,
        contentType: 'image/png',
        academyId: academyId,
      );
      final downloadUrl = uploaded.publicUrl;
      if (downloadUrl == null) {
        if (mounted) context.showError('Upload concluído sem URL pública.');
        return;
      }

      final service = SettingsService(academyId);
      await service.updateLogo(downloadUrl);

      ref.invalidate(academySettingsProvider);
      await _loadSettings();

      if (mounted) context.showSuccess('Logo atualizado!');
    } catch (e) {
      if (mounted) context.showError('Erro ao fazer upload: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSettings,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader()),
                  SliverToBoxAdapter(child: _buildTabs()),
                  SliverToBoxAdapter(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _buildTabContent(),
                    ),
                  ),
                  SliverToBoxAdapter(child: _buildSaveButton()),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          if (_settings?.name != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _settings!.name,
                style: AppTheme.labelMedium.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          const Spacer(),
          IconButton(
            onPressed: _loadSettings,
            icon: const Icon(LucideIcons.refreshCw, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.surface,
              foregroundColor: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedTabIndex == index;
          return GestureDetector(
            onTap: () => setState(() => _selectedTabIndex = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.textPrimary : AppTheme.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isSelected ? AppTheme.textPrimary : AppTheme.divider,
                ),
              ),
              child: Center(
                child: Text(
                  _tabs[index],
                  style: AppTheme.bodySmall.copyWith(
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return AcademyTab(
          key: const ValueKey('academy'),
          logoUrl: _settings?.logoUrl,
          onPickLogo: _pickAndUploadLogo,
          nameController: _nameController,
          sloganController: _sloganController,
          emailController: _emailController,
          phoneController: _phoneController,
          cnpjController: _cnpjController,
          addressController: _addressController,
          cityController: _cityController,
          stateController: _stateController,
          zipCodeController: _zipCodeController,
          birthDateController: _birthDateController,
          onPickBirthDate: _pickBirthDate,
        );
      case 1:
        return FinancialTab(
          key: const ValueKey('financial'),
          pixKeyController: _pixKeyController,
          pixKeyType: _pixKeyType,
          onPixKeyTypeChanged: (v) => setState(() => _pixKeyType = v),
          abacatePayEnabled: _abacatePayEnabled,
          onAbacatePayChanged: (v) => setState(() => _abacatePayEnabled = v),
          asaasEnabled: _asaasEnabled,
          kycStatus: _kycStatus,
          kycOnboardingUrl: _kycOnboardingUrl,
          isCheckingKyc: _isCheckingKyc,
          onCheckKyc: _checkKycStatus,
        );
      case 2:
        return MonitorsTab(
          key: const ValueKey('monitors'),
          monitorIds: _monitorIds,
          linkedStudents: _linkedStudents,
          isLoadingMonitors: _isLoadingMonitors,
          onAddMonitor: _addMonitor,
          onRemoveMonitor: _removeMonitor,
        );
      case 3:
        return FeaturesTab(
          key: const ValueKey('features'),
          autoGraduationEnabled: _autoGraduationEnabled,
          onAutoGraduationChanged: (v) =>
              setState(() => _autoGraduationEnabled = v),
          autoGraduationAttendancesController:
              _autoGraduationAttendancesController,
          useClassWeights: _useClassWeights,
          onUseClassWeightsChanged: (v) =>
              setState(() => _useClassWeights = v),
          studentCheckinEnabled: _studentCheckinEnabled,
          onStudentCheckinChanged: (v) =>
              setState(() => _studentCheckinEnabled = v),
          storeEnabled: _storeEnabled,
          onStoreEnabledChanged: (v) => setState(() => _storeEnabled = v),
          storePublished: _storePublished,
          onStorePublishedChanged: (v) => setState(() => _storePublished = v),
          storeWelcomeController: _storeWelcomeController,
          storeMinAmountController: _storeMinAmountController,
          storeCreditCardEnabled: _storeCreditCardEnabled,
        );
      case 4:
        return const TeamTabContent();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSaveButton() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveSettings,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.textPrimary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          disabledBackgroundColor: AppTheme.textPrimary.withValues(alpha: 0.5),
        ),
        child: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.save, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Salvar Configuracoes',
                    style: AppTheme.bodyMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
