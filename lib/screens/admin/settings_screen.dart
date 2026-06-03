import 'dart:async';
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
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/feedback_utils.dart';
import '../../core/formatters.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/portal_providers.dart';
import '../../services/services.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/common/delete_account_helper.dart';
import 'mercado_pago_connect_screen.dart';
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

  // Unsaved-changes tracking. `_savedSnapshot` is the serialized state at the
  // last load/save; the screen is "dirty" when the current snapshot differs.
  String? _savedSnapshot;
  bool _lastDirty = false;

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
  bool _mpConnected = false;
  bool _mpBusy = false;
  bool _storeEnabled = false;
  bool _storePublished = false;
  bool _storeCreditCardEnabled = false;
  bool _studentCheckinEnabled = false;
  bool _journalVisibleToStudents = true;
  bool _rankingVisibleToStudents = true;

  // Musculação check-in (schedule-less)
  String _musculacaoCheckinMode = 'manual'; // 'manual' | 'qr' | 'button'
  final Map<int, ({String open, String close})> _operatingHours = {};

  // Muay Thai graduation ladder ('cbmt' | 'cbmtt')
  String _muaythaiGradeSystem = muaythaiVariantCbmt;

  // Auto-graduation + class weights
  bool _autoGraduationEnabled = false;
  bool _useClassWeights = false;
  String _graduationMode = 'manual'; // 'manual' | 'auto'
  bool _graduationProgressVisibleToStudents = false;
  final _autoGraduationAttendancesController = TextEditingController(
    text: '70',
  );
  // Per-sport, per-belt requirements: sportValue → {gradeId → classes}.
  // Empty → uses the global "Presencas para graduar" field.
  Map<String, Map<String, int>> _graduationRequirementsBySport = {};


  // KYC
  String _kycStatus = 'not_checked';
  String? _kycOnboardingUrl;
  bool _isCheckingKyc = false;

  final _tabs = [
    'Academia',
    'Financeiro',
    'Funcionalidades',
    'Equipe',
  ];

  @override
  void initState() {
    super.initState();
    // Text edits should surface the "unsaved changes" bar like toggles do.
    for (final c in <TextEditingController>[
      _nameController,
      _sloganController,
      _cnpjController,
      _emailController,
      _phoneController,
      _addressController,
      _cityController,
      _stateController,
      _zipCodeController,
      _birthDateController,
      _pixKeyController,
      _storeWelcomeController,
      _storeMinAmountController,
      _autoGraduationAttendancesController,
    ]) {
      c.addListener(_onFieldChanged);
    }
    _loadSettings();
  }

  /// Serialized snapshot of every field saved by [_saveSettings]. Comparing it
  /// to [_savedSnapshot] tells us whether there are unsaved changes — covering
  /// all fields without touching each onChanged callback.
  String _snapshot() {
    final hours = (_operatingHours.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => '${e.key}:${e.value.open}-${e.value.close}')
        .join(',');
    return [
      _nameController.text,
      _sloganController.text,
      _cnpjController.text,
      _emailController.text,
      _phoneController.text,
      _addressController.text,
      _cityController.text,
      _stateController.text,
      _zipCodeController.text,
      _birthDateController.text,
      _pixKeyController.text,
      _storeWelcomeController.text,
      _storeMinAmountController.text,
      _autoGraduationAttendancesController.text,
      _pixKeyType?.value ?? '',
      _abacatePayEnabled,
      _asaasEnabled,
      _storeEnabled,
      _storePublished,
      _storeCreditCardEnabled,
      _studentCheckinEnabled,
      _journalVisibleToStudents,
      _rankingVisibleToStudents,
      _musculacaoCheckinMode,
      hours,
      _muaythaiGradeSystem,
      _autoGraduationEnabled,
      _useClassWeights,
      _graduationMode,
      _graduationProgressVisibleToStudents,
    ].join('|');
  }

  bool get _isDirty =>
      _savedSnapshot != null && _snapshot() != _savedSnapshot;

  void _onFieldChanged() {
    if (_isLoading) return; // ignore programmatic population during load
    final dirty = _isDirty;
    if (dirty != _lastDirty && mounted) {
      setState(() => _lastDirty = dirty);
    }
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
          _cnpjController.text = formatCpfCnpj(settings.cnpj);
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
          _mpConnected = settings.mpConnected;
          _storeEnabled = settings.storeEnabled;
          _storePublished = settings.storePublished;
          _storeCreditCardEnabled = settings.storeCreditCardEnabled;
          _studentCheckinEnabled = settings.studentCheckinEnabled;
          _journalVisibleToStudents = settings.journalVisibleToStudents;
          _rankingVisibleToStudents = settings.rankingVisibleToStudents;
          _musculacaoCheckinMode = settings.musculacaoCheckinMode;
          _operatingHours
            ..clear()
            ..addAll(settings.operatingHours.byDay);
          _muaythaiGradeSystem = settings.muaythaiGradeSystem;
          _autoGraduationEnabled = settings.autoGraduationEnabled;
          _useClassWeights = settings.useClassWeights;
          _graduationMode = settings.graduationMode;
          _graduationProgressVisibleToStudents =
              settings.graduationProgressVisibleToStudents;
          if (settings.autoGraduationAttendances != null) {
            _autoGraduationAttendancesController.text = settings
                .autoGraduationAttendances
                .toString();
          }
          _graduationRequirementsBySport = {
            for (final e in settings.graduationRequirementsBySport.entries)
              e.key: Map<String, int>.of(e.value),
          };
        });
      }

      // Auto-check KYC status if Asaas is enabled
      if (_asaasEnabled) {
        _checkKycStatus();
      }

      _savedSnapshot = _snapshot();
      _lastDirty = false;
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final service = SettingsService(FirebaseService.academyId);
      final attendancesValue = int.tryParse(
        _autoGraduationAttendancesController.text,
      );

      // Fire all writes concurrently (they target the same academy doc). This
      // matters offline: Firestore applies each write to the local cache the
      // moment it's called, but the returned Future only completes on the
      // server ack — which never arrives while offline. Awaiting them
      // sequentially hangs forever on the first one (the infinite spinner).
      // Future.wait + a timeout keeps the UI responsive; offline the data is
      // already saved locally and syncs when the connection returns.
      final futures = <Future<void>>[
        service.updateBasicInfo(
          name: _nameController.text,
          cnpj: _cnpjController.text.isEmpty ? null : onlyDigits(_cnpjController.text),
          email: _emailController.text.isEmpty ? null : _emailController.text,
          phone: _phoneController.text.isEmpty ? null : _phoneController.text,
          address:
              _addressController.text.isEmpty ? null : _addressController.text,
          city: _cityController.text.isEmpty ? null : _cityController.text,
          state: _stateController.text.isEmpty ? null : _stateController.text,
          zipCode:
              _zipCodeController.text.isEmpty ? null : _zipCodeController.text,
          responsibleBirthDate: _birthDateController.text.isEmpty
              ? null
              : _birthDateController.text,
        ),
        // PIX: set when key+type are valid, otherwise clear it. (Before, a
        // cleared or partial PIX was silently skipped and never persisted.)
        service.updatePix(
          pixKey: _pixKeyController.text,
          pixKeyType: _pixKeyType,
        ),
        service.updateBranding(
          portalSlogan:
              _sloganController.text.isEmpty ? null : _sloganController.text,
        ),
        service.updateStoreSettings(
          enabled: _storeEnabled,
          published: _storePublished,
          creditCardEnabled: _storeCreditCardEnabled,
          welcomeMessage: _storeWelcomeController.text.isEmpty
              ? null
              : _storeWelcomeController.text,
          minOrderAmount: _storeMinAmountController.text.isNotEmpty
              ? double.tryParse(_storeMinAmountController.text)
              : null,
        ),
        service.toggleAbacatePay(_abacatePayEnabled),
        service.toggleAsaas(_asaasEnabled),
        service.toggleStudentCheckin(_studentCheckinEnabled),
        service.updateJournalVisibility(_journalVisibleToStudents),
        service.updateRankingVisibility(_rankingVisibleToStudents),
        service.updateMusculacaoCheckin(
          mode: _musculacaoCheckinMode,
          operatingHours: OperatingHours(Map.of(_operatingHours)),
        ),
        service.updateMuaythaiGradeSystem(_muaythaiGradeSystem),
        service.updateAutoGraduation(
          _autoGraduationEnabled,
          attendances: attendancesValue,
          mode: _graduationMode,
          progressVisibleToStudents: _graduationProgressVisibleToStudents,
          requirementsBySport: _graduationRequirementsBySport,
        ),
        service.updateUseClassWeights(_useClassWeights),
      ];

      var savedOffline = false;
      try {
        await Future.wait(futures).timeout(const Duration(seconds: 12));
      } on TimeoutException {
        // Writes are committed locally; only the server ack is pending.
        savedOffline = true;
      }

      // Invalidate the settings provider to refresh UI across the app
      ref.invalidate(academySettingsProvider);
      ref.invalidate(academyNameProvider);
      ref.invalidate(pixInfoProvider);

      if (mounted) {
        setState(() {
          _savedSnapshot = _snapshot();
          _lastDirty = false;
        });
        context.showSuccess(
          savedOffline
              ? 'Salvo. Sera sincronizado quando houver conexao.'
              : 'Configuracoes salvas!',
        );
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
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

      // Upload to Firebase Storage
      final file = File(croppedFile.path);
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('academies')
          .child(FirebaseService.academyId)
          .child('logo.png');

      await storageRef.putFile(file);
      final downloadUrl = await storageRef.getDownloadURL();

      // Update settings
      final service = SettingsService(FirebaseService.academyId);
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
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !_isDirty) return;
        final action = await _showUnsavedDialog();
        if (!mounted || action == null || action == 'cancel') return;
        if (action == 'save') {
          await _saveSettings();
          if (mounted && !_isDirty) Navigator.of(context).maybePop();
        } else {
          // Discard: drop changes (we're leaving) and pop.
          setState(() {
            _savedSnapshot = _snapshot();
            _lastDirty = false;
          });
          if (mounted) Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: RefreshIndicator(
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
                  ),
                  // Sticky unsaved-changes bar — always visible while dirty,
                  // regardless of scroll position or how the user navigates.
                  if (_isDirty) _buildUnsavedBar(),
                ],
              ),
      ),
    );
  }

  Future<String?> _showUnsavedDialog() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alteracoes nao salvas'),
        content: const Text(
          'Voce tem alteracoes que ainda nao foram salvas. O que deseja fazer?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Continuar editando'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: Text('Descartar', style: TextStyle(color: AppTheme.error)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Widget _buildUnsavedBar() {
    return Material(
      elevation: 8,
      color: AppTheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Icon(Icons.error_outline, size: 18, color: AppTheme.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Alteracoes nao salvas',
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: _isSaving ? null : _loadSettings,
                child: const Text('Descartar'),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: _isSaving ? null : _saveSettings,
                child: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Salvar'),
              ),
            ],
          ),
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
        return _buildFeaturesTab();
      case 3:
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
                  inputFormatters: [CpfCnpjInputFormatter()],
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

          // Mercado Pago (recebimentos do admin via PIX, direto na conta dele)
          _buildMercadoPagoCard(),

          // AbacatePay legado — só enquanto a academia não conectou o MP.
          if (!_mpConnected) ...[
            const SizedBox(height: 16),
            _SettingsCard(
              title: 'AbacatePay (legado)',
              icon: LucideIcons.plug,
              child: _ModernSwitch(
                title: 'AbacatePay',
                subtitle: 'Cobranca via PIX (sera substituido pelo Mercado Pago)',
                value: _abacatePayEnabled,
                onChanged: (value) {
                  setState(() => _abacatePayEnabled = value);
                },
                icon: LucideIcons.zap,
                iconColor: Colors.green,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMercadoPagoCard() {
    return _SettingsCard(
      title: 'Mercado Pago',
      icon: LucideIcons.creditCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _mpConnected
                ? 'Conta conectada. Os pagamentos PIX dos alunos caem direto na sua conta do Mercado Pago (sem taxa da plataforma).'
                : 'Conecte sua conta do Mercado Pago para receber as mensalidades e pedidos da loja via PIX, direto na sua conta (sem taxa da plataforma).',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          if (_mpConnected)
            Row(
              children: [
                Icon(LucideIcons.checkCircle, size: 18, color: AppTheme.success),
                const SizedBox(width: 8),
                Text(
                  'Conectado',
                  style: AppTheme.titleSmall.copyWith(
                    color: AppTheme.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _mpBusy ? null : _disconnectMercadoPago,
                  child: const Text('Desconectar'),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _mpBusy ? null : _connectMercadoPago,
                icon: _mpBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.link, size: 18),
                label: Text(_mpBusy ? 'Conectando...' : 'Conectar Mercado Pago'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _connectMercadoPago() async {
    // Dedicated full-screen flow (deep-link + backoff polling + states).
    final connected = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MercadoPagoConnectScreen(
          academyId: FirebaseService.academyId,
        ),
      ),
    );
    if (connected == true && mounted) {
      setState(() {
        _mpConnected = true;
        _abacatePayEnabled = false;
        _asaasEnabled = false;
      });
    }
  }

  Future<void> _disconnectMercadoPago() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Desconectar Mercado Pago'),
        content: const Text(
          'Os alunos nao poderao mais pagar via Mercado Pago ate reconectar. Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _mpBusy = true);
    try {
      final ok = await MercadoPagoService(FirebaseService.academyId).disconnect();
      if (mounted && ok) {
        setState(() => _mpConnected = false);
        context.showSuccess('Mercado Pago desconectado.');
      } else if (mounted) {
        context.showError('Falha ao desconectar.');
      }
    } finally {
      if (mounted) setState(() => _mpBusy = false);
    }
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

  /// Per-sport, per-belt graduation requirements editor. Optional — a sport
  /// left empty uses the global "Presencas para graduar" value.
  Widget _buildPerBeltRequirements() {
    final gradedSports = sportOptions
        .where((s) => getSport(s).gradeSystem != GradeSystem.none)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Requisitos por faixa (opcional)',
          style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Defina, por esporte, quantas presencas cada faixa exige. O valor '
          'vale para cada grau da faixa. Esportes sem configuracao usam o '
          'padrao acima.',
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 8),
        ...gradedSports.map((sportId) {
          final configured =
              _graduationRequirementsBySport[sportId.value] ?? const {};
          final count = configured.values.where((v) => v > 0).length;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                getSport(sportId).icon,
                color: sportChipColors[sportId],
              ),
              title: Text(getSport(sportId).label),
              subtitle: Text(
                count > 0 ? '$count faixa(s) configurada(s)' : 'Usando padrao',
              ),
              trailing: const Icon(LucideIcons.chevronRight, size: 18),
              onTap: () => _editSportRequirements(sportId),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _editSportRequirements(SportId sportId) async {
    // Full ladder, including the honorary belts above black (BJJ coral/vermelha
    // etc.). Attendance auto-graduation never reaches these, but admins can see
    // and note the requirement for the complete belt list.
    final grades = getGradesForSport(
      sportId,
      muaythaiVariant: _muaythaiGradeSystem,
    ).toList();

    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (ctx) => _GraduationRequirementsDialog(
        sportLabel: getSport(sportId).label,
        grades: grades,
        initial: _graduationRequirementsBySport[sportId.value] ?? const {},
      ),
    );

    if (result == null) return; // cancelled — no change
    setState(() {
      if (result.isEmpty) {
        _graduationRequirementsBySport.remove(sportId.value);
      } else {
        _graduationRequirementsBySport[sportId.value] = result;
      }
    });
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
            title: 'Graduacao por Presencas',
            icon: LucideIcons.award,
            child: Column(
              children: [
                _ModernSwitch(
                  title: 'Habilitar Graduacao por Presencas',
                  subtitle:
                      'Libera a aba Graduacao no menu admin e o card de progresso para alunos',
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
                    label: 'Presencas para graduar (padrao)',
                    hint: '70',
                    icon: LucideIcons.target,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  _buildPerBeltRequirements(),
                  const SizedBox(height: 16),
                  // Mode selector — auto vs manual approval
                  _GraduationModeSelector(
                    value: _graduationMode,
                    onChanged: (mode) =>
                        setState(() => _graduationMode = mode),
                  ),
                  const SizedBox(height: 16),
                  _ModernSwitch(
                    title: 'Aluno ve seu progresso',
                    subtitle:
                        'Exibe X/Y aulas e barra de progresso no portal do aluno',
                    value: _graduationProgressVisibleToStudents,
                    onChanged: (value) => setState(
                      () => _graduationProgressVisibleToStudents = value,
                    ),
                    icon: LucideIcons.eye,
                    iconColor: AppTheme.info,
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
                            _graduationMode == 'auto'
                                ? 'Modo automatico: ao atingir o numero de presencas, o aluno e promovido automaticamente para o proximo grau.'
                                : 'Modo manual: alunos elegiveis sao destacados na lista; o mestre confirma cada graduacao na tela Graduacao.',
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

          // Musculação check-in (schedule-less modality)
          _SettingsCard(
            title: 'Check-in da Musculacao',
            icon: Icons.fitness_center,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Como os alunos de musculacao (sem horario de aula) registram presenca.',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                _MusculacaoCheckinModeSelector(
                  value: _musculacaoCheckinMode,
                  onChanged: (m) => setState(() => _musculacaoCheckinMode = m),
                ),
                if (_musculacaoCheckinMode != 'manual') ...[
                  const SizedBox(height: 16),
                  _OperatingHoursEditor(
                    hours: _operatingHours,
                    onChanged: (next) => setState(() {
                      _operatingHours
                        ..clear()
                        ..addAll(next);
                    }),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Muay Thai graduation ladder
          _SettingsCard(
            title: 'Graduacao do Muay Thai',
            icon: Icons.flash_on_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'O Muay Thai nao tem graduacao oficial: cada federacao usa a sua. Escolha qual sequencia de cores (prajied) a academia vai adotar.',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                _MuaythaiGradeSystemSelector(
                  value: _muaythaiGradeSystem,
                  onChanged: (v) => setState(() => _muaythaiGradeSystem = v),
                ),
                const SizedBox(height: 14),
                _MuaythaiLadderPreview(variant: _muaythaiGradeSystem),
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

          // Jornal da Academia (student-facing feed visibility)
          _SettingsCard(
            title: 'Jornal da Academia',
            icon: LucideIcons.newspaper,
            child: _ModernSwitch(
              title: 'Mostrar Jornal da Academia para alunos',
              subtitle:
                  'Controla o feed de noticias, seminarios e novidades exibido no portal do aluno',
              value: _journalVisibleToStudents,
              onChanged: (value) async {
                setState(() => _journalVisibleToStudents = value);
                final service = SettingsService(FirebaseService.academyId);
                await service.updateJournalVisibility(value);
                if (!mounted) return;
                ref.invalidate(academySettingsProvider);
                setState(() {
                  _savedSnapshot = _snapshot();
                  _lastDirty = false;
                });
                context.showSuccess('Configuracoes salvas!');
              },
              icon: LucideIcons.newspaper,
              iconColor: AppTheme.primary,
            ),
          ),

          const SizedBox(height: 16),

          // Ranking de Turmas (student-facing leaderboard visibility)
          _SettingsCard(
            title: 'Ranking de Turmas',
            icon: LucideIcons.trophy,
            child: _ModernSwitch(
              title: 'Mostrar ranking de turmas para alunos',
              subtitle:
                  'Controla o placar de presencas por turma exibido no portal do aluno',
              value: _rankingVisibleToStudents,
              onChanged: (value) async {
                setState(() => _rankingVisibleToStudents = value);
                final service = SettingsService(FirebaseService.academyId);
                await service.updateRankingVisibility(value);
                if (!mounted) return;
                ref.invalidate(academySettingsProvider);
                setState(() {
                  _savedSnapshot = _snapshot();
                  _lastDirty = false;
                });
                context.showSuccess('Configuracoes salvas!');
              },
              icon: LucideIcons.trophy,
              iconColor: AppTheme.primary,
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
  final List<TextInputFormatter>? inputFormatters;

  const _ModernTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.maxLines = 1,
    this.readOnly = false,
    this.onTap,
    this.inputFormatters,
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
            inputFormatters: inputFormatters,
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
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: disabled
                                ? AppTheme.textSecondary
                                : AppTheme.textPrimary,
                          ),
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

/// Segmented selector used in the Funcionalidades tab to pick between
/// 'manual' (mestre confirma cada graduação) and 'auto' (promote on
/// threshold). Renders as two side-by-side cards with the active one
/// highlighted in the primary color.
class _GraduationModeSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _GraduationModeSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Modo de graduacao',
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ModeCard(
                title: 'Manual',
                subtitle: 'Mestre aprova',
                icon: LucideIcons.handMetal,
                selected: value == 'manual',
                onTap: () => onChanged('manual'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ModeCard(
                title: 'Automatico',
                subtitle: 'Promove ao bater',
                icon: LucideIcons.zap,
                selected: value == 'auto',
                onTap: () => onChanged('auto'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Picks which Muay Thai prajied ladder the academy uses. 'cbmt' is the
/// blue-based CBMT/CMTB system; 'cbmtt' is the CBMTT traditional (white→gold).
class _MuaythaiGradeSystemSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _MuaythaiGradeSystemSelector({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ModeCard(
            title: 'CBMT / CMTB',
            subtitle: 'Branca a Preta',
            icon: LucideIcons.shield,
            selected: value == muaythaiVariantCbmt,
            onTap: () => onChanged(muaythaiVariantCbmt),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ModeCard(
            title: 'CBMT Tradicional',
            subtitle: 'Branca a Ouro',
            icon: LucideIcons.award,
            selected: value == muaythaiVariantCbmtt,
            onTap: () => onChanged(muaythaiVariantCbmtt),
          ),
        ),
      ],
    );
  }
}

/// Shows the ordered colors of the selected Muay Thai ladder so the admin can
/// confirm it matches their federation before saving.
class _MuaythaiLadderPreview extends StatelessWidget {
  final String variant;

  const _MuaythaiLadderPreview({required this.variant});

  @override
  Widget build(BuildContext context) {
    final grades = getGradesForSport(
      SportId.muaythai,
      muaythaiVariant: variant,
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: grades.map((g) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Body color + a small tip slice for "ponta"/combo grades.
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: g.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.divider),
                ),
                clipBehavior: Clip.antiAlias,
                child: g.tipColor != null
                    ? Align(
                        alignment: Alignment.centerRight,
                        child: FractionallySizedBox(
                          widthFactor: 0.5,
                          child: Container(color: g.tipColor),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 6),
              Text(
                g.label,
                style: AppTheme.labelSmall
                    .copyWith(color: AppTheme.textPrimary),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.primary : AppTheme.textSecondary;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.08)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.bodyMedium.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppTheme.labelSmall.copyWith(
                      color: color.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Selector for how musculação students record attendance: staff-driven
/// ('manual'), fixed QR ('qr') or in-app button ('button').
class _MusculacaoCheckinModeSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _MusculacaoCheckinModeSelector({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Modo de check-in',
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _ModeCard(
          title: 'Recepcao (manual)',
          subtitle: 'A recepcao marca a presenca',
          icon: Icons.how_to_reg,
          selected: value == 'manual',
          onTap: () => onChanged('manual'),
        ),
        const SizedBox(height: 8),
        _ModeCard(
          title: 'QR fixo',
          subtitle: 'Aluno escaneia o QR na recepcao',
          icon: Icons.qr_code_2,
          selected: value == 'qr',
          onTap: () => onChanged('qr'),
        ),
        const SizedBox(height: 8),
        _ModeCard(
          title: 'Botao no app',
          subtitle: 'Aluno toca "Cheguei" no portal',
          icon: Icons.touch_app,
          selected: value == 'button',
          onTap: () => onChanged('button'),
        ),
      ],
    );
  }
}

/// Per-weekday operating-hours editor. Keys are 0=Sun..6=Sat to match
/// [OperatingHours]; displayed Monday-first. A weekday without an entry is
/// "closed". Emits a brand-new map on every change so the parent can setState.
class _OperatingHoursEditor extends StatelessWidget {
  final Map<int, ({String open, String close})> hours;
  final ValueChanged<Map<int, ({String open, String close})>> onChanged;

  const _OperatingHoursEditor({required this.hours, required this.onChanged});

  static const _labels = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab'];
  static const _order = [1, 2, 3, 4, 5, 6, 0];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Horario de funcionamento',
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Libera o check-in apenas dentro do horario. Sem dias configurados = liberado sempre.',
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 8),
        ..._order.map((dow) => _row(context, dow)),
      ],
    );
  }

  Widget _row(BuildContext context, int dow) {
    final window = hours[dow];
    final isOpen = window != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              _labels[dow],
              style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Switch(
            value: isOpen,
            onChanged: (v) {
              final next = Map<int, ({String open, String close})>.from(hours);
              if (v) {
                next[dow] = (open: '06:00', close: '22:00');
              } else {
                next.remove(dow);
              }
              onChanged(next);
            },
          ),
          const SizedBox(width: 8),
          if (isOpen)
            Expanded(
              child: Row(
                children: [
                  _timeChip(context, window.open, (t) {
                    final next =
                        Map<int, ({String open, String close})>.from(hours);
                    next[dow] = (open: t, close: window.close);
                    onChanged(next);
                  }),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      'as',
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  _timeChip(context, window.close, (t) {
                    final next =
                        Map<int, ({String open, String close})>.from(hours);
                    next[dow] = (open: window.open, close: t);
                    onChanged(next);
                  }),
                ],
              ),
            )
          else
            Text(
              'Fechado',
              style: AppTheme.labelSmall.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _timeChip(
    BuildContext context,
    String hhmm,
    ValueChanged<String> onPick,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final parts = hhmm.split(':');
        final initial = TimeOfDay(
          hour: int.tryParse(parts.first) ?? 6,
          minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
        );
        final picked = await showTimePicker(
          context: context,
          initialTime: initial,
        );
        if (picked != null) {
          final h = picked.hour.toString().padLeft(2, '0');
          final m = picked.minute.toString().padLeft(2, '0');
          onPick('$h:$m');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Text(hhmm, style: AppTheme.bodyMedium),
      ),
    );
  }
}

/// Dialog to edit the per-belt graduation requirements of one sport. Returns
/// the {gradeId: classes} map on save (empty = use the academy default), or
/// null if cancelled.
class _GraduationRequirementsDialog extends StatefulWidget {
  const _GraduationRequirementsDialog({
    required this.sportLabel,
    required this.grades,
    required this.initial,
  });

  final String sportLabel;
  final List<GradeDefinition> grades;
  final Map<String, int> initial;

  @override
  State<_GraduationRequirementsDialog> createState() =>
      _GraduationRequirementsDialogState();
}

class _GraduationRequirementsDialogState
    extends State<_GraduationRequirementsDialog> {
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final g in widget.grades)
        g.id: TextEditingController(
          text: (widget.initial[g.id] ?? 0) > 0
              ? widget.initial[g.id].toString()
              : '',
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Requisitos — ${widget.sportLabel}'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              'Presencas por faixa. Em branco = usa o padrao da academia.',
              style:
                  AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            ...widget.grades.map(
              (g) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(g.label)),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: _controllers[g.id],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          hintText: 'padrao',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, <String, int>{}),
          child: const Text('Limpar tudo'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final out = <String, int>{};
            _controllers.forEach((id, c) {
              final n = int.tryParse(c.text.trim());
              if (n != null && n > 0) out[id] = n;
            });
            Navigator.pop(context, out);
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
