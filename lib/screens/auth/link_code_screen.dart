import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/link_code_service.dart';
import '../../services/firebase_service.dart';

/// Link Code Screen - Create account using access code
class LinkCodeScreen extends ConsumerStatefulWidget {
  const LinkCodeScreen({super.key});

  @override
  ConsumerState<LinkCodeScreen> createState() => _LinkCodeScreenState();
}

enum _Step { code, register, success }

class _LinkCodeScreenState extends ConsumerState<LinkCodeScreen> {
  final _codeFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  _Step _currentStep = _Step.code;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;
  LinkCode? _validatedLinkCode;

  @override
  void dispose() {
    _codeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _validateCode() async {
    if (!_codeFormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final linkCodeService = LinkCodeService(FirebaseService.academyId);
      final validation = await linkCodeService.validate(_codeController.text.trim().toUpperCase());

      if (!validation.valid) {
        setState(() {
          _errorMessage = validation.error;
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _validatedLinkCode = validation.linkCode;
        _currentStep = _Step.register;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro ao validar codigo. Tente novamente.';
        _isLoading = false;
      });
    }
  }

  Future<void> _createAccount() async {
    if (!_registerFormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final linkCodeService = LinkCodeService(FirebaseService.academyId);

      // Create Firebase account with the student name from the link code
      final userCredential = await authService.createAccountWithLinkCode(
        _emailController.text.trim(),
        _passwordController.text,
        _validatedLinkCode!.studentName,
        _validatedLinkCode!.studentId,
      );

      // Mark the code as used
      await linkCodeService.markAsUsed(
        _validatedLinkCode!.code,
        userCredential.user!.uid,
      );

      setState(() {
        _currentStep = _Step.success;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = _getErrorMessage(e);
        _isLoading = false;
      });
    }
  }

  String _getErrorMessage(dynamic error) {
    if (error.toString().contains('email-already-in-use')) {
      return 'Este email ja esta em uso';
    } else if (error.toString().contains('invalid-email')) {
      return 'Email invalido';
    } else if (error.toString().contains('weak-password')) {
      return 'Senha muito fraca. Use pelo menos 6 caracteres.';
    }
    return 'Erro ao criar conta. Tente novamente.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () {
            if (_currentStep == _Step.register) {
              setState(() {
                _currentStep = _Step.code;
                _errorMessage = null;
              });
            } else {
              context.go('/login');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _buildCurrentStep(),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case _Step.code:
        return _buildCodeStep();
      case _Step.register:
        return _buildRegisterStep();
      case _Step.success:
        return _buildSuccessStep();
    }
  }

  Widget _buildCodeStep() {
    return Form(
      key: _codeFormKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: Icon(
                LucideIcons.key,
                size: 40,
                color: AppTheme.primary,
              ),
            ),
          ).animate().fadeIn(duration: 300.ms).scale(
                begin: const Offset(0.8, 0.8),
              ),

          const SizedBox(height: 32),

          // Title
          Text(
            'Codigo de Acesso',
            style: AppTheme.displaySmall,
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 100.ms),

          const SizedBox(height: 8),

          Text(
            'Digite o codigo de 6 caracteres fornecido pela academia',
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: 40),

          // Error message
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.errorLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.alertCircle,
                    color: AppTheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn().shake(),

          if (_errorMessage != null) const SizedBox(height: 24),

          // Code field
          TextFormField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _validateCode(),
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
            ),
            decoration: const InputDecoration(
              labelText: 'Codigo',
              hintText: 'ABC123',
              counterText: '',
              prefixIcon: Icon(LucideIcons.key, size: 20),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Informe o codigo';
              }
              if (value.length != 6) {
                return 'O codigo deve ter 6 caracteres';
              }
              return null;
            },
          ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.1),

          const SizedBox(height: 32),

          // Validate button
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _validateCode,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Validar Codigo'),
            ),
          ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),

          const SizedBox(height: 24),

          // Back to login
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Ja tem uma conta? ',
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('Entrar'),
              ),
            ],
          ).animate().fadeIn(delay: 500.ms),
        ],
      ),
    );
  }

  Widget _buildRegisterStep() {
    return Form(
      key: _registerFormKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Success indicator
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.checkCircle,
                  color: AppTheme.success,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Codigo validado!',
                        style: AppTheme.bodyMedium.copyWith(
                          color: AppTheme.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Aluno: ${_validatedLinkCode!.studentName}',
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.success,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(),

          const SizedBox(height: 24),

          // Title
          Text(
            'Criar sua conta',
            style: AppTheme.displaySmall,
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 100.ms),

          const SizedBox(height: 8),

          Text(
            'Complete seu cadastro para acessar o app',
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: 32),

          // Error message
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.errorLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.alertCircle,
                    color: AppTheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn().shake(),

          if (_errorMessage != null) const SizedBox(height: 24),

          // Name field (read-only, from link code)
          TextFormField(
            initialValue: _validatedLinkCode!.studentName,
            enabled: false,
            decoration: InputDecoration(
              labelText: 'Nome',
              prefixIcon: const Icon(LucideIcons.user, size: 20),
              filled: true,
              fillColor: AppTheme.surface,
            ),
          ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.1),

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
              if (value == null || value.isEmpty) {
                return 'Informe seu email';
              }
              if (!value.contains('@')) {
                return 'Email invalido';
              }
              return null;
            },
          ).animate().fadeIn(delay: 400.ms).slideX(begin: -0.1),

          const SizedBox(height: 16),

          // Password field
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Senha',
              hintText: 'Minimo 6 caracteres',
              prefixIcon: const Icon(LucideIcons.lock, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Informe uma senha';
              }
              if (value.length < 6) {
                return 'A senha deve ter pelo menos 6 caracteres';
              }
              return null;
            },
          ).animate().fadeIn(delay: 500.ms).slideX(begin: -0.1),

          const SizedBox(height: 16),

          // Confirm password field
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _createAccount(),
            decoration: InputDecoration(
              labelText: 'Confirmar senha',
              hintText: 'Repita a senha',
              prefixIcon: const Icon(LucideIcons.lock, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword ? LucideIcons.eyeOff : LucideIcons.eye,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Confirme sua senha';
              }
              if (value != _passwordController.text) {
                return 'As senhas nao coincidem';
              }
              return null;
            },
          ).animate().fadeIn(delay: 600.ms).slideX(begin: -0.1),

          const SizedBox(height: 32),

          // Create account button
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _createAccount,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Criar conta'),
            ),
          ).animate().fadeIn(delay: 700.ms).slideY(begin: 0.1),
        ],
      ),
    );
  }

  Widget _buildSuccessStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Success icon
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(
              LucideIcons.checkCircle,
              size: 60,
              color: AppTheme.success,
            ),
          ),
        ).animate().fadeIn(duration: 300.ms).scale(
              begin: const Offset(0.8, 0.8),
            ),

        const SizedBox(height: 32),

        // Title
        Text(
          'Conta criada!',
          style: AppTheme.displaySmall,
          textAlign: TextAlign.center,
        ).animate().fadeIn(delay: 100.ms),

        const SizedBox(height: 8),

        Text(
          'Sua conta foi vinculada ao aluno ${_validatedLinkCode!.studentName}',
          style: AppTheme.bodyMedium.copyWith(
            color: AppTheme.textSecondary,
          ),
          textAlign: TextAlign.center,
        ).animate().fadeIn(delay: 200.ms),

        const SizedBox(height: 40),

        // Continue button
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: () => context.go('/portal'),
            child: const Text('Acessar o app'),
          ),
        ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),
      ],
    );
  }
}
