import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';

/// Document type for registration
enum _DocumentType { cpf, cnpj }

/// Create Academy Screen - Multi-step form for professors/owners
class CreateAcademyScreen extends ConsumerStatefulWidget {
  const CreateAcademyScreen({super.key});

  @override
  ConsumerState<CreateAcademyScreen> createState() => _CreateAcademyScreenState();
}

class _CreateAcademyScreenState extends ConsumerState<CreateAcademyScreen> {
  final _pageController = PageController();
  int _currentStep = 0;

  // Professor form
  final _professorFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Academy form
  final _academyFormKey = GlobalKey<FormState>();
  final _academyNameController = TextEditingController();
  final _documentController = TextEditingController();
  _DocumentType _documentType = _DocumentType.cpf;

  // General state
  bool _isLoading = false;
  String? _errorMessage;
  bool _acceptedTerms = false;

  // Open terms URL
  Future<void> _openTermsUrl() async {
    final uri = Uri.parse('https://bjjeasy.netlify.app/termsofservice');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _academyNameController.dispose();
    _documentController.dispose();
    super.dispose();
  }

  // ============================================
  // Document Formatting & Validation
  // ============================================
  
  /// Format CPF: 000.000.000-00
  String _formatCpf(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 3) return digits;
    if (digits.length <= 6) return '${digits.substring(0, 3)}.${digits.substring(3)}';
    if (digits.length <= 9) return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6)}';
    return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9, digits.length.clamp(0, 11))}';
  }

  /// Format CNPJ: 00.000.000/0000-00
  String _formatCnpj(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 2) return digits;
    if (digits.length <= 5) return '${digits.substring(0, 2)}.${digits.substring(2)}';
    if (digits.length <= 8) return '${digits.substring(0, 2)}.${digits.substring(2, 5)}.${digits.substring(5)}';
    if (digits.length <= 12) return '${digits.substring(0, 2)}.${digits.substring(2, 5)}.${digits.substring(5, 8)}/${digits.substring(8)}';
    return '${digits.substring(0, 2)}.${digits.substring(2, 5)}.${digits.substring(5, 8)}/${digits.substring(8, 12)}-${digits.substring(12, digits.length.clamp(0, 14))}';
  }

  /// Validate CPF check digits
  bool _validateCpf(String cpf) {
    final digits = cpf.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 11) return false;
    if (RegExp(r'^(\d)\1{10}$').hasMatch(digits)) return false;

    int sum = 0;
    for (int i = 0; i < 9; i++) {
      sum += int.parse(digits[i]) * (10 - i);
    }
    int rest = (sum * 10) % 11;
    if (rest == 10) rest = 0;
    if (rest != int.parse(digits[9])) return false;

    sum = 0;
    for (int i = 0; i < 10; i++) {
      sum += int.parse(digits[i]) * (11 - i);
    }
    rest = (sum * 10) % 11;
    if (rest == 10) rest = 0;
    if (rest != int.parse(digits[10])) return false;

    return true;
  }

  /// Validate CNPJ check digits
  bool _validateCnpj(String cnpj) {
    final digits = cnpj.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 14) return false;
    if (RegExp(r'^(\d)\1{13}$').hasMatch(digits)) return false;

    // First check digit
    const weights1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      sum += int.parse(digits[i]) * weights1[i];
    }
    int rest = sum % 11;
    int digit1 = rest < 2 ? 0 : 11 - rest;
    if (digit1 != int.parse(digits[12])) return false;

    // Second check digit
    const weights2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    sum = 0;
    for (int i = 0; i < 13; i++) {
      sum += int.parse(digits[i]) * weights2[i];
    }
    rest = sum % 11;
    int digit2 = rest < 2 ? 0 : 11 - rest;
    if (digit2 != int.parse(digits[13])) return false;

    return true;
  }

  void _onDocumentChanged(String value) {
    final formatted = _documentType == _DocumentType.cpf
        ? _formatCpf(value)
        : _formatCnpj(value);
    if (formatted != _documentController.text) {
      _documentController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  String? _validateDocument(String? value) {
    if (value == null || value.isEmpty) {
      return _documentType == _DocumentType.cpf
          ? 'Informe o CPF do responsável'
          : 'Informe o CNPJ da academia';
    }
    
    final digits = value.replaceAll(RegExp(r'\D'), '');
    
    if (_documentType == _DocumentType.cpf) {
      if (digits.length != 11) return 'CPF deve ter 11 dígitos';
      if (!_validateCpf(value)) return 'CPF inválido';
    } else {
      if (digits.length != 14) return 'CNPJ deve ter 14 dígitos';
      if (!_validateCnpj(value)) return 'CNPJ inválido';
    }
    
    return null;
  }

  // ============================================
  // Navigation
  // ============================================
  void _goToStep(int step) {
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
    setState(() {
      _currentStep = step;
      _errorMessage = null;
    });
  }

  void _handleNext() {
    if (_currentStep == 0) {
      if (_professorFormKey.currentState?.validate() ?? false) {
        _goToStep(1);
      }
    } else if (_currentStep == 1) {
      if (!(_academyFormKey.currentState?.validate() ?? false)) return;

      if (!_acceptedTerms) {
        setState(() {
          _errorMessage = 'Você precisa aceitar os Termos de Serviço para continuar.';
        });
        return;
      }

      _handleCreateAcademy();
    }
  }

  // ============================================
  // Create Academy
  // ============================================
  Future<void> _handleCreateAcademy() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final container = ProviderScope.containerOf(context);

    try {
      // Show overlay
      container.read(creatingAccountStudentNameProvider.notifier).state = '';
      container.read(isCreatingAccountProvider.notifier).state = true;

      final documentDigits = _documentController.text.replaceAll(RegExp(r'\D'), '');

      final authService = ref.read(authServiceProvider);
      await authService.createAcademyAccount(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _nameController.text.trim(),
        academyName: _academyNameController.text.trim(),
        documentType: _documentType == _DocumentType.cpf ? 'cpf' : 'cnpj',
        documentNumber: documentDigits,
      );

      // All Firestore documents are created. Force Riverpod to reload user data.
      container.invalidate(currentUserProvider);

      // Poll until currentUserProvider returns valid data with admin role (max 10 seconds)
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final userAsync = container.read(currentUserProvider);
        if (userAsync.hasValue && userAsync.value != null) {
          final user = userAsync.value!;
          if (user.academyId != null && user.isAdmin) {
            break;
          }
          container.invalidate(currentUserProvider);
        }
        if (userAsync.hasError) {
          container.invalidate(currentUserProvider);
        }
      }

      // Dismiss overlay - the router will naturally redirect to /admin
      container.read(isCreatingAccountProvider.notifier).state = false;
    } catch (e) {
      // Dismiss overlay on error (if it was shown)
      container.read(isCreatingAccountProvider.notifier).state = false;

      if (mounted) {
        setState(() {
          _errorMessage = _getErrorMessage(e);
          _isLoading = false;
        });
      }
    }
  }

  String _getErrorMessage(dynamic error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('email-already-in-use')) {
      return 'Este email já está em uso. Faça login ou use outro email.';
    } else if (msg.contains('invalid-email')) {
      return 'Email inválido';
    } else if (msg.contains('weak-password')) {
      return 'Senha muito fraca. Use pelo menos 6 caracteres.';
    } else if (msg.contains('permission-denied') || msg.contains('permission denied')) {
      return 'Erro de permissão. Entre em contato com o suporte.';
    } else if (msg.contains('network')) {
      return 'Erro de conexão. Verifique sua internet.';
    }
    return 'Erro ao criar academia. Tente novamente.';
  }

  // ============================================
  // Build Methods
  // ============================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: _currentStep == 2
            ? null
            : IconButton(
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: () {
                  if (_currentStep > 0 && _currentStep < 2) {
                    _goToStep(_currentStep - 1);
                  } else {
                    context.go('/login');
                  }
                },
              ),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Step Indicator
            if (_currentStep < 2)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _buildStepIndicator(),
              ),

            // Page content
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildProfessorStep(),
                  _buildAcademyStep(),
                  _buildSuccessStep(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    final steps = ['Seus Dados', 'Academia', 'Pronto!'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(steps.length, (index) {
          final isCompleted = index < _currentStep;
          final isCurrent = index == _currentStep;
          return Row(
            children: [
              Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (isCompleted || isCurrent) ? AppTheme.primary : AppTheme.divider,
                    ),
                    child: Center(
                      child: isCompleted
                          ? const Icon(LucideIcons.check, size: 16, color: Colors.white)
                          : Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isCurrent ? Colors.white : AppTheme.textDisabled,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    steps[index],
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                      color: (isCompleted || isCurrent) ? AppTheme.textPrimary : AppTheme.textDisabled,
                    ),
                  ),
                ],
              ),
              if (index < steps.length - 1)
                Container(
                  width: 32,
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 16, left: 8, right: 8),
                  color: isCompleted ? AppTheme.primary : AppTheme.divider,
                ),
            ],
          );
        }),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  // ============================================
  // Step 1 - Professor Data
  // ============================================
  Widget _buildProfessorStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _professorFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Logo instead of icon
            Center(
              child: Image.asset(
                'assets/images/logo.png',
                width: 80,
                height: 80,
              ),
            ).animate().scale(begin: const Offset(0.8, 0.8), duration: 400.ms, curve: Curves.easeOut),

            const SizedBox(height: 20),

            Text(
              'Seus Dados',
              style: AppTheme.displaySmall,
              textAlign: TextAlign.center,
            ).animate().fadeIn(duration: 300.ms),

            const SizedBox(height: 8),

            Text(
              'Crie sua conta de professor/administrador',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 100.ms),

            const SizedBox(height: 32),

            // Error message
            if (_errorMessage != null && _currentStep == 0)
              _buildErrorBanner().animate().fadeIn().shake(),
            if (_errorMessage != null && _currentStep == 0) const SizedBox(height: 16),

            // Name field
            TextFormField(
              controller: _nameController,
              keyboardType: TextInputType.name,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome completo',
                hintText: 'Seu nome',
                prefixIcon: Icon(LucideIcons.user, size: 20),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Informe seu nome';
                if (value.trim().length < 3) return 'Nome deve ter pelo menos 3 caracteres';
                return null;
              },
            ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.1),

            const SizedBox(height: 16),

            // Email field
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'seu@email.com',
                prefixIcon: Icon(LucideIcons.mail, size: 20),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Informe seu email';
                if (!value.contains('@')) return 'Email inválido';
                return null;
              },
            ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.1),

            const SizedBox(height: 16),

            // Password field
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Senha',
                hintText: 'Mínimo 6 caracteres',
                prefixIcon: const Icon(LucideIcons.lock, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Informe uma senha';
                if (value.length < 6) return 'A senha deve ter pelo menos 6 caracteres';
                return null;
              },
            ).animate().fadeIn(delay: 400.ms).slideX(begin: -0.1),

            const SizedBox(height: 16),

            // Confirm password field
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _handleNext(),
              decoration: InputDecoration(
                labelText: 'Confirmar senha',
                hintText: 'Repita a senha',
                prefixIcon: const Icon(LucideIcons.lock, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword ? LucideIcons.eyeOff : LucideIcons.eye,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Confirme sua senha';
                if (value != _passwordController.text) return 'As senhas não coincidem';
                return null;
              },
            ).animate().fadeIn(delay: 500.ms).slideX(begin: -0.1),

            const SizedBox(height: 32),

            // Next button
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _handleNext,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Continuar'),
                    const SizedBox(width: 8),
                    const Icon(LucideIcons.arrowRight, size: 18),
                  ],
                ),
              ),
            ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.1),

            const SizedBox(height: 24),

            // Login link
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Já tem uma conta? ',
                  style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
                ),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Entrar'),
                ),
              ],
            ).animate().fadeIn(delay: 700.ms),
          ],
        ),
      ),
    );
  }

  // ============================================
  // Step 2 - Academy Data
  // ============================================
  Widget _buildAcademyStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _academyFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Logo instead of icon
            Center(
              child: Image.asset(
                'assets/images/logo.png',
                width: 80,
                height: 80,
              ),
            ).animate().scale(begin: const Offset(0.8, 0.8), duration: 400.ms, curve: Curves.easeOut),

            const SizedBox(height: 20),

            Text(
              'Dados da Academia',
              style: AppTheme.displaySmall,
              textAlign: TextAlign.center,
            ).animate().fadeIn(duration: 300.ms),

            const SizedBox(height: 8),

            Text(
              'Configure sua academia de Jiu-Jitsu',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 100.ms),

            const SizedBox(height: 32),

            // Error message
            if (_errorMessage != null && _currentStep == 1)
              _buildErrorBanner().animate().fadeIn().shake(),
            if (_errorMessage != null && _currentStep == 1) const SizedBox(height: 16),

            // Academy name field
            TextFormField(
              controller: _academyNameController,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome da Academia',
                hintText: 'Ex: Team Alpha Jiu-Jitsu',
                prefixIcon: Icon(LucideIcons.graduationCap, size: 20),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Informe o nome da academia';
                if (value.trim().length < 3) return 'Nome deve ter pelo menos 3 caracteres';
                return null;
              },
            ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.1),

            const SizedBox(height: 24),

            // Document type toggle
            Text(
              'Documento do responsável',
              style: AppTheme.labelLarge.copyWith(color: AppTheme.textSecondary),
            ).animate().fadeIn(delay: 250.ms),
            
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: _DocumentTypeCard(
                    icon: LucideIcons.user,
                    title: 'CPF',
                    subtitle: 'Pessoa Física',
                    selected: _documentType == _DocumentType.cpf,
                    onTap: () {
                      setState(() {
                        _documentType = _DocumentType.cpf;
                        _documentController.clear();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DocumentTypeCard(
                    icon: LucideIcons.building2,
                    title: 'CNPJ',
                    subtitle: 'Empresa',
                    selected: _documentType == _DocumentType.cnpj,
                    onTap: () {
                      setState(() {
                        _documentType = _DocumentType.cnpj;
                        _documentController.clear();
                      });
                    },
                  ),
                ),
              ],
            ).animate().fadeIn(delay: 300.ms),

            const SizedBox(height: 16),

            // Document field
            TextFormField(
              controller: _documentController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.\-/]')),
                LengthLimitingTextInputFormatter(_documentType == _DocumentType.cpf ? 14 : 18),
              ],
              onChanged: _onDocumentChanged,
              decoration: InputDecoration(
                labelText: _documentType == _DocumentType.cpf ? 'CPF' : 'CNPJ',
                hintText: _documentType == _DocumentType.cpf ? '000.000.000-00' : '00.000.000/0000-00',
                prefixIcon: const Icon(LucideIcons.fileText, size: 20),
              ),
              validator: _validateDocument,
            ).animate().fadeIn(delay: 350.ms).slideX(begin: -0.1),

            const SizedBox(height: 24),

            // Terms checkbox
            CheckboxListTile(
              value: _acceptedTerms,
              onChanged: (value) {
                setState(() {
                  _acceptedTerms = value ?? false;
                });
              },
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  children: [
                    const TextSpan(text: 'Aceito os '),
                    TextSpan(
                      text: 'Termos e Condições de Serviço',
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()..onTap = _openTermsUrl,
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(delay: 400.ms),

            const SizedBox(height: 32),

            // Create button
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleNext,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Criar Academia'),
              ),
            ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.1),
          ],
        ),
      ),
    );
  }

  // ============================================
  // Step 3 - Success
  // ============================================
  Widget _buildSuccessStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),

          // Success icon
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF43E97B), Color(0xFF38F9D7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF43E97B).withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(LucideIcons.checkCircle, size: 44, color: Colors.white),
          )
              .animate()
              .scale(begin: const Offset(0, 0), duration: 600.ms, curve: Curves.elasticOut)
              .rotate(begin: -0.5, duration: 600.ms),

          const SizedBox(height: 28),

          Text(
            'Academia criada com sucesso!',
            style: AppTheme.displaySmall.copyWith(color: AppTheme.success),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2),

          const SizedBox(height: 12),

          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              children: [
                const TextSpan(text: 'Sua academia '),
                TextSpan(
                  text: _academyNameController.text,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                const TextSpan(text: ' está pronta para uso.'),
              ],
            ),
          ).animate().fadeIn(delay: 400.ms),

          const SizedBox(height: 28),

          // Info box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.successLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.success.withValues(alpha: 0.2)),
            ),
            child: Text(
              'Você já pode acessar o painel e começar a cadastrar seus alunos.',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.1),

          const SizedBox(height: 40),

          // Access button
          SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.go('/login'),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.logIn, size: 18),
                  const SizedBox(width: 8),
                  const Text('Fazer Login Agora'),
                ],
              ),
            ),
          ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.1),

          const SizedBox(height: 12),

          Text(
            'Use suas credenciais para acessar',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textDisabled),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 700.ms),
        ],
      ),
    );
  }

  // ============================================
  // Helpers
  // ============================================
  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.errorLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.alertCircle, color: AppTheme.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentTypeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _DocumentTypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? primary.withValues(alpha: 0.08)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? primary : AppTheme.divider,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected
                      ? primary.withValues(alpha: 0.15)
                      : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: selected ? primary : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppTheme.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected ? primary : AppTheme.textPrimary,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AnimatedScale(
                duration: const Duration(milliseconds: 180),
                scale: selected ? 1 : 0,
                child: Icon(
                  LucideIcons.checkCircle2,
                  size: 18,
                  color: primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
