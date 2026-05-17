import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../api/dto/upload_dto.dart' as api_upload;
import '../../api/feature_flags.dart';
import '../../api/repositories.dart' as tatami_repos;
import '../../core/constants.dart';
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../providers/portal_providers.dart';
import '../../services/services.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/common/delete_account_helper.dart';
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

      // Load linked students for monitors selection
      await _loadLinkedStudents();

      // Auto-check KYC status if Asaas is enabled
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

      // Filter students that have linkedUserId and are active
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
      if (mounted) {
        context.showSuccess('Monitor adicionado!');
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro: $e');
      }
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
      if (mounted) {
        context.showSuccess('Monitor removido!');
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro: $e');
      }
    } finally {
      setState(() => _isLoadingMonitors = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final service = SettingsService(FirebaseService.academyId);

      // Save basic info
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

      // Save PIX info
      if (_pixKeyController.text.isNotEmpty && _pixKeyType != null) {
        await service.updatePixInfo(_pixKeyController.text, _pixKeyType!);
      }

      // Save branding
      await service.updateBranding(
        portalSlogan: _sloganController.text.isEmpty
            ? null
            : _sloganController.text,
      );

      // Save store settings
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

      // Save payment provider settings
      await service.toggleAbacatePay(_abacatePayEnabled);
      await service.toggleAsaas(_asaasEnabled);

      // Save student check-in settings
      await service.toggleStudentCheckin(_studentCheckinEnabled);

      // Save auto-graduation settings
      final attendancesValue = int.tryParse(
        _autoGraduationAttendancesController.text,
      );
      await service.updateAutoGraduation(
        _autoGraduationEnabled,
        attendances: attendancesValue,
      );
      await service.updateUseClassWeights(_useClassWeights);

      // Invalidate the settings provider to refresh UI across the app
      ref.invalidate(academySettingsProvider);
      ref.invalidate(academyNameProvider);
      ref.invalidate(pixInfoProvider);

      if (mounted) {
        context.showSuccess('Configuracoes salvas!');
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro: $e');
      }
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
      if (mounted) {
        context.showError('Erro ao verificar documentos');
      }
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

      // Crop to 1:1 aspect ratio
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
      final flags = ref.read(tatamiFlagsProvider);
      String? downloadUrl;

      // Sem flag dedicada `useTatamiUploads` ainda (8 flags atuais não
      // cobrem uploads). Usamos `useTatamiWrites` como proxy — same risk
      // profile (mutações server-side). Fix de flag dedicada vai no
      // Sprint 3 quando o catálogo for ampliado.
      if (flags.useTatamiWrites) {
        try {
          final repo = ref.read(tatami_repos.uploadsRepoProvider);
          final uploaded = await repo.uploadFileFromDisk(
            purpose: api_upload.ApiUploadPurpose.academySettings,
            file: file,
            contentType: 'image/png',
            academyId: academyId,
          );
          downloadUrl = uploaded.publicUrl;
        } catch (_) {
          // Fallback transparente para o Firebase Storage legacy.
        }
      }

      if (downloadUrl == null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('academies')
            .child(academyId)
            .child('logo.png');

        await storageRef.putFile(file);
        downloadUrl = await storageRef.getDownloadURL();
      }

      // Update settings
      final service = SettingsService(academyId);
      await service.updateLogo(downloadUrl);

      // Invalidate providers to refresh UI across the app
      ref.invalidate(academySettingsProvider);

      // Reload settings
      await _loadSettings();

      if (mounted) {
        context.showSuccess('Logo atualizado!');
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro ao fazer upload: $e');
      }
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
                  // Header
                  SliverToBoxAdapter(child: _buildHeader()),

                  // Tabs
                  SliverToBoxAdapter(child: _buildTabs()),

                  // Content based on tab
                  SliverToBoxAdapter(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _buildTabContent(),
                    ),
                  ),

                  // Save button
                  SliverToBoxAdapter(child: _buildSaveButton()),

                  // Bottom padding
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
        return _buildAcademyTab();
      case 1:
        return _buildFinancialTab();
      case 2:
        return _buildMonitorsTab();
      case 3:
        return _buildFeaturesTab();
      case 4:
        return const TeamTabContent();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildAcademyTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        key: const ValueKey('academy'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // Logo Section
          _SettingsCard(
            title: 'Logo e Identidade',
            icon: LucideIcons.image,
            child: Column(
              children: [
                // Logo preview
                GestureDetector(
                  onTap: _pickAndUploadLogo,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.divider, width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: (_settings?.logoUrl ?? '').isEmpty
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                LucideIcons.upload,
                                color: AppTheme.textSecondary,
                                size: 24,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Adicionar',
                                style: AppTheme.labelSmall.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          )
                        : Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Positioned.fill(
                                child: AppCachedImage(
                                  imageUrl: _settings!.logoUrl,
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppTheme.textPrimary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  LucideIcons.pencil,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Toque para ${_settings?.logoUrl != null ? 'alterar' : 'adicionar'} o logo',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Name and Slogan
          _SettingsCard(
            title: 'Informacoes Basicas',
            icon: LucideIcons.building2,
            child: Column(
              children: [
                _ModernTextField(
                  controller: _nameController,
                  label: 'Nome da Academia',
                  hint: 'Ex: Academia de Jiu-Jitsu',
                  icon: LucideIcons.building,
                ),
                const SizedBox(height: 16),
                _ModernTextField(
                  controller: _sloganController,
                  label: 'Frase / Slogan',
                  hint: 'Ex: Transformando vidas atraves do Jiu-Jitsu',
                  icon: LucideIcons.quote,
                  maxLines: 2,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Contact Info
          _SettingsCard(
            title: 'Contato',
            icon: LucideIcons.phone,
            child: Column(
              children: [
                _ModernTextField(
                  controller: _emailController,
                  label: 'E-mail',
                  hint: 'contato@academia.com',
                  icon: LucideIcons.mail,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                _ModernTextField(
                  controller: _phoneController,
                  label: 'Telefone',
                  hint: '(11) 99999-9999',
                  icon: LucideIcons.phone,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                _ModernTextField(
                  controller: _cnpjController,
                  label: 'CPF/CNPJ',
                  hint: 'CPF do responsavel ou CNPJ da academia',
                  icon: LucideIcons.fileText,
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Address
          _SettingsCard(
            title: 'Endereco',
            icon: LucideIcons.mapPin,
            child: Column(
              children: [
                _ModernTextField(
                  controller: _addressController,
                  label: 'Endereco',
                  hint: 'Rua, numero, bairro',
                  icon: LucideIcons.home,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _ModernTextField(
                        controller: _cityController,
                        label: 'Cidade',
                        hint: 'Sao Paulo',
                        icon: LucideIcons.building2,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ModernTextField(
                        controller: _stateController,
                        label: 'UF',
                        hint: 'SP',
                        icon: LucideIcons.map,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _ModernTextField(
                        controller: _zipCodeController,
                        label: 'CEP',
                        hint: '00000-000',
                        icon: LucideIcons.mailbox,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ModernTextField(
                        controller: _birthDateController,
                        label: 'Nascimento do Responsavel',
                        hint: 'Selecione a data',
                        icon: LucideIcons.calendarDays,
                        readOnly: true,
                        onTap: _pickBirthDate,
                      ),
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

  Widget _buildFinancialTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        key: const ValueKey('financial'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // PIX Settings
          _SettingsCard(
            title: 'Chave PIX',
            icon: LucideIcons.qrCode,
            child: Column(
              children: [
                _ModernTextField(
                  controller: _pixKeyController,
                  label: 'Chave PIX',
                  hint: 'Sua chave PIX',
                  icon: LucideIcons.key,
                ),
                const SizedBox(height: 16),
                _ModernDropdown<PixKeyType>(
                  label: 'Tipo da Chave',
                  value: _pixKeyType,
                  items: PixKeyType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type.label),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _pixKeyType = value);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // AbacatePay Integration
          _SettingsCard(
            title: 'Integracoes',
            icon: LucideIcons.plug,
            child: Column(
              children: [
                _ModernSwitch(
                  title: 'AbacatePay',
                  subtitle: 'Cobranca automatica via PIX',
                  value: _abacatePayEnabled,
                  onChanged: (value) {
                    setState(() => _abacatePayEnabled = value);
                  },
                  icon: LucideIcons.zap,
                  iconColor: Colors.green,
                ),
                const SizedBox(height: 12),
                _ModernSwitch(
                  title: 'Asaas',
                  subtitle: 'Pagamentos via PIX e cartao (subconta)',
                  value: false,
                  onChanged: null,
                  icon: LucideIcons.creditCard,
                  iconColor: Colors.grey,
                  disabled: true,
                ),
              ],
            ),
          ),

          // KYC Section - only when Asaas is enabled
          if (_asaasEnabled) ...[
            const SizedBox(height: 16),
            _buildKycSection(),
          ],
        ],
      ),
    );
  }

  Widget _buildKycSection() {
    return _SettingsCard(
      title: 'Verificacao de Documentos (KYC)',
      icon: LucideIcons.fileCheck,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Envie documentos para verificacao e aprovacao da subconta',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          _buildKycContent(),
        ],
      ),
    );
  }

  Widget _buildKycContent() {
    // Not checked
    if (_kycStatus == 'not_checked') {
      return ElevatedButton.icon(
        onPressed: _isCheckingKyc ? null : _checkKycStatus,
        icon: _isCheckingKyc
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(LucideIcons.fileSearch, size: 18),
        label: Text(_isCheckingKyc ? 'Verificando...' : 'Verificar Documentos'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.textPrimary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }

    // Approved
    if (_kycStatus == 'approved') {
      return _buildKycInfoBox(
        color: AppTheme.success,
        icon: LucideIcons.checkCircle,
        title: 'Documentos Aprovados!',
        message: 'Sua conta esta totalmente verificada.',
      );
    }

    // Pending review
    if (_kycStatus == 'pending_review') {
      return Column(
        children: [
          _buildKycInfoBox(
            color: AppTheme.info,
            icon: LucideIcons.clock,
            title: 'Documentos em Analise',
            message:
                'Seus documentos estao sendo verificados. A aprovacao pode levar ate 48 horas.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isCheckingKyc ? null : _checkKycStatus,
            icon: _isCheckingKyc
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.refreshCw, size: 16),
            label: Text(_isCheckingKyc ? 'Atualizando...' : 'Atualizar Status'),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      );
    }

    // Rejected or pending upload — single verification button
    final isRejected = _kycStatus == 'rejected';

    return Column(
      children: [
        _buildKycInfoBox(
          color: isRejected ? AppTheme.error : AppTheme.warning,
          icon: LucideIcons.alertTriangle,
          title: isRejected ? 'Documentos Rejeitados' : 'Documentos Pendentes',
          message: isRejected
              ? 'Envie novamente os documentos solicitados.'
              : 'Complete a verificacao para ativar sua conta.',
        ),
        const SizedBox(height: 16),
        if (_kycOnboardingUrl != null)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final uri = Uri.parse(_kycOnboardingUrl!);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(LucideIcons.externalLink, size: 18),
              label: Text(
                isRejected ? 'Reenviar Documentos' : 'Iniciar Verificacao',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          )
        else
          _buildKycInfoBox(
            color: AppTheme.info,
            icon: LucideIcons.info,
            title: 'Link nao disponivel',
            message: 'Clique em "Atualizar Status" para tentar novamente.',
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _isCheckingKyc ? null : _checkKycStatus,
          icon: _isCheckingKyc
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.refreshCw, size: 16),
          label: Text(_isCheckingKyc ? 'Atualizando...' : 'Atualizar Status'),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKycInfoBox({
    required Color color,
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(message, style: AppTheme.bodySmall.copyWith(color: color)),
          if (action != null) ...[const SizedBox(height: 12), action],
        ],
      ),
    );
  }

  Widget _buildMonitorsTab() {
    // Get current monitors (students who are in monitorIds)
    final currentMonitors = _linkedStudents
        .where((s) => _monitorIds.contains(s['id']))
        .toList();

    // Get available students (linked but not monitors)
    final availableStudents = _linkedStudents
        .where((s) => !_monitorIds.contains(s['id']))
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        key: const ValueKey('monitors'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // Add Monitor Section
          _SettingsCard(
            title: 'Adicionar Monitor',
            icon: LucideIcons.userPlus,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selecione um aluno com conta vinculada para adiciona-lo como monitor.',
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                if (availableStudents.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.info,
                          color: AppTheme.textSecondary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _linkedStudents.isEmpty
                                ? 'Nenhum aluno possui conta vinculada.'
                                : 'Todos os alunos vinculados ja sao monitores.',
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: null,
                      hint: Text(
                        'Selecionar aluno',
                        style: AppTheme.bodyMedium.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      items: availableStudents.map((student) {
                        final name = student['nickname'] ?? student['fullName'];
                        return DropdownMenuItem(
                          value: student['id'] as String,
                          child: Text(name),
                        );
                      }).toList(),
                      onChanged: _isLoadingMonitors
                          ? null
                          : (value) {
                              if (value != null) {
                                _addMonitor(value);
                              }
                            },
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      dropdownColor: AppTheme.surface,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Current Monitors List
          _SettingsCard(
            title: 'Monitores Atuais (${currentMonitors.length})',
            icon: LucideIcons.shield,
            child: currentMonitors.isEmpty
                ? Container(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          LucideIcons.shield,
                          color: AppTheme.textDisabled,
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Nenhum monitor cadastrado',
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: currentMonitors.map((monitor) {
                      final name = monitor['nickname'] ?? monitor['fullName'];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  name.substring(0, 1).toUpperCase(),
                                  style: AppTheme.titleMedium.copyWith(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: AppTheme.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (monitor['nickname'] != null)
                                    Text(
                                      monitor['fullName'],
                                      style: AppTheme.labelSmall.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: _isLoadingMonitors
                                  ? null
                                  : () =>
                                        _removeMonitor(monitor['id'] as String),
                              icon: Icon(
                                LucideIcons.x,
                                color: AppTheme.error,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),

          const SizedBox(height: 16),

          // Info about permissions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.info, color: Colors.blue, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Permissoes do Monitor',
                      style: AppTheme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '• Fazer chamada de presenca\n• Visualizar, cadastrar e editar alunos',
                  style: AppTheme.bodySmall.copyWith(
                    color: Colors.blue.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Monitores NAO tem acesso a: Financeiro, Relatorios, Configuracoes.',
                  style: AppTheme.labelSmall.copyWith(
                    color: Colors.blue.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        key: const ValueKey('features'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // Auto-graduation settings
          _SettingsCard(
            title: 'Graduacao Automatica',
            icon: LucideIcons.award,
            child: Column(
              children: [
                _ModernSwitch(
                  title: 'Habilitar Graduacao Automatica',
                  subtitle:
                      'Sinaliza alunos elegiveis com base no numero de presencas',
                  value: _autoGraduationEnabled,
                  onChanged: (value) {
                    setState(() => _autoGraduationEnabled = value);
                  },
                  icon: LucideIcons.award,
                  iconColor: AppTheme.warning,
                ),
                if (_autoGraduationEnabled) ...[
                  const SizedBox(height: 16),
                  _ModernTextField(
                    controller: _autoGraduationAttendancesController,
                    label: 'Presencas para graduar',
                    hint: '70',
                    icon: LucideIcons.target,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.info.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(LucideIcons.info, size: 18, color: AppTheme.info),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Alunos serao destacados na lista quando atingirem o numero configurado. A graduacao em si precisa ser confirmada por um admin.',
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.info,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ModernSwitch(
                    title: 'Usar pesos por turma',
                    subtitle:
                        'Aula particular pode valer 2 ou mais (configurado por turma)',
                    value: _useClassWeights,
                    onChanged: (value) {
                      setState(() => _useClassWeights = value);
                    },
                    icon: LucideIcons.scale,
                    iconColor: AppTheme.info,
                  ),
                  if (_useClassWeights) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.warning.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            LucideIcons.info,
                            size: 18,
                            color: AppTheme.warning,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Defina o peso de cada turma na tela de Turmas. Turmas sem peso configurado contam como 1.',
                              style: AppTheme.labelSmall.copyWith(
                                color: AppTheme.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Student Check-in Settings
          _SettingsCard(
            title: 'Check-in de Alunos',
            icon: LucideIcons.userCheck,
            child: Column(
              children: [
                _ModernSwitch(
                  title: 'Habilitar Check-in',
                  subtitle: 'Alunos podem marcar presenca pelo app',
                  value: _studentCheckinEnabled,
                  onChanged: (value) {
                    setState(() => _studentCheckinEnabled = value);
                  },
                  icon: LucideIcons.userCheck,
                  iconColor: AppTheme.success,
                ),
                if (_studentCheckinEnabled) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.info.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(LucideIcons.info, size: 18, color: AppTheme.info),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Alunos podem fazer check-in de 30 min antes ate 1h apos o fim da aula. O professor confirma as presencas na tela de chamada.',
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.info,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Store Settings
          _SettingsCard(
            title: 'Loja',
            icon: LucideIcons.shoppingBag,
            child: Column(
              children: [
                _ModernSwitch(
                  title: 'Habilitar Loja',
                  subtitle: 'Ativar modulo de produtos e vendas',
                  value: _storeEnabled,
                  onChanged: (value) {
                    setState(() => _storeEnabled = value);
                  },
                  icon: LucideIcons.store,
                  iconColor: AppTheme.warning,
                ),
                if (_storeEnabled) ...[
                  const SizedBox(height: 16),
                  _ModernSwitch(
                    title: 'Loja Publicada',
                    subtitle: 'Tornar a loja visivel para alunos',
                    value: _storePublished,
                    onChanged: (value) {
                      setState(() => _storePublished = value);
                    },
                    icon: LucideIcons.eye,
                    iconColor: AppTheme.success,
                  ),
                  const SizedBox(height: 16),
                  _ModernTextField(
                    controller: _storeWelcomeController,
                    label: 'Mensagem de Boas-vindas',
                    hint: 'Bem-vindo a nossa loja!',
                    icon: LucideIcons.messageSquare,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  _ModernTextField(
                    controller: _storeMinAmountController,
                    label: 'Pedido Minimo (R\$)',
                    hint: '0.00',
                    icon: LucideIcons.dollarSign,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ModernSwitch(
                    title: 'Permitir Cartao de Credito',
                    subtitle: 'Em breve',
                    value: false,
                    onChanged: null,
                    icon: LucideIcons.creditCard,
                    iconColor: AppTheme.textSecondary,
                    disabled: true,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Account section with logout, legal links, and account deletion
          _SettingsCard(
            title: 'Conta',
            icon: LucideIcons.user,
            child: Column(
              children: [
                // Legal links
                _AccountActionTile(
                  icon: LucideIcons.fileText,
                  title: 'Termos de Uso',
                  onTap: () => _openUrl(AppConstants.termsOfServiceUrl),
                ),
                const SizedBox(height: 8),
                _AccountActionTile(
                  icon: LucideIcons.shield,
                  title: 'Politica de Privacidade',
                  onTap: () => _openUrl(AppConstants.privacyPolicyUrl),
                ),
                const SizedBox(height: 8),
                // Sign out
                _AccountActionTile(
                  icon: LucideIcons.logOut,
                  title: 'Sair da conta',
                  subtitle: 'Encerrar sessao atual',
                  isDestructive: true,
                  onTap: () async {
                    final authService = ref.read(authServiceProvider);
                    await authService.signOut();
                  },
                ),
                const SizedBox(height: 8),
                // Delete account (App Store / Play Store policy)
                _AccountActionTile(
                  icon: LucideIcons.trash2,
                  title: 'Excluir minha conta',
                  subtitle: 'Remover permanentemente seus dados',
                  isDestructive: true,
                  onTap: () =>
                      DeleteAccountHelper.showConfirmation(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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
                  Icon(LucideIcons.save, size: 20),
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

/// Settings Card Widget
class _SettingsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppTheme.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: AppTheme.titleMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

/// Modern Text Field
class _ModernTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool readOnly;
  final VoidCallback? onTap;

  const _ModernTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.maxLines = 1,
    this.readOnly = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            readOnly: readOnly,
            onTap: onTap,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textDisabled,
              ),
              prefixIcon: Icon(icon, color: AppTheme.textSecondary, size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Modern Dropdown
class _ModernDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  const _ModernDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: DropdownButtonFormField<T>(
            value: value,
            items: items,
            onChanged: onChanged,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            dropdownColor: AppTheme.surface,
          ),
        ),
      ],
    );
  }
}

/// Modern Switch
class _ModernSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData icon;
  final Color iconColor;
  final bool disabled;

  const _ModernSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.icon,
    required this.iconColor,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = disabled ? AppTheme.textSecondary : iconColor;

    return Opacity(
      opacity: disabled ? 0.6 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: value && !disabled
              ? effectiveColor.withValues(alpha: 0.05)
              : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value && !disabled
                ? effectiveColor.withValues(alpha: 0.2)
                : AppTheme.divider,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: effectiveColor.withValues(
                  alpha: value && !disabled ? 0.2 : 0.1,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: effectiveColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: AppTheme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: disabled
                              ? AppTheme.textSecondary
                              : AppTheme.textPrimary,
                        ),
                      ),
                      if (disabled) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Em breve',
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.warning,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    subtitle,
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: disabled ? null : onChanged,
              activeColor: effectiveColor,
            ),
          ],
        ),
      ),
    );
  }
}

/// Tile used inside the admin "Conta" card for legal links,
/// sign-out and account deletion. Mirrors the visual styling
/// of _ModernSwitch but acts as a tap target.
class _AccountActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isDestructive;
  final VoidCallback onTap;

  const _AccountActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isDestructive ? AppTheme.error : AppTheme.textPrimary;
    final bgColor = isDestructive
        ? AppTheme.error.withValues(alpha: 0.05)
        : AppTheme.surfaceVariant;
    final borderColor = isDestructive
        ? AppTheme.error.withValues(alpha: 0.2)
        : AppTheme.divider;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDestructive ? 0.1 : 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: AppTheme.labelSmall.copyWith(
                        color: isDestructive
                            ? accent.withValues(alpha: 0.7)
                            : AppTheme.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              color: isDestructive ? accent : AppTheme.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
