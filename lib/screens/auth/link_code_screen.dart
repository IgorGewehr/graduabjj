import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../services/global_user_service.dart';
import '../../services/instructor_link_code_service.dart';
import '../../services/link_code_service.dart';

/// Link Code Screen - Create account using access code
class LinkCodeScreen extends ConsumerStatefulWidget {
  const LinkCodeScreen({super.key});

  @override
  ConsumerState<LinkCodeScreen> createState() => _LinkCodeScreenState();
}

enum _Step { code, register, creating, success }

class _LinkCodeScreenState extends ConsumerState<LinkCodeScreen> {
  final _codeFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _cpfController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  _Step _currentStep = _Step.code;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;
  LinkCode? _validatedLinkCode;

  // Instructor flow state. Populated when the entered code is 8 chars and
  // resolves in /instructorLinkCodes — switches the form to a minimal
  // name+email+password layout and routes submit to redeemInstructorCode.
  InstructorLinkCode? _validatedInstructorCode;
  String? _validatedInstructorAcademyId;
  final _fullNameController = TextEditingController();

  bool get _isInstructorMode => _validatedInstructorCode != null;

  @override
  void dispose() {
    _codeController.dispose();
    _cpfController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  /// Format CPF string: 000.000.000-00
  String _formatCpf(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 3) return digits;
    if (digits.length <= 6) return '${digits.substring(0, 3)}.${digits.substring(3)}';
    if (digits.length <= 9) return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6)}';
    return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9, digits.length.clamp(0, 11))}';
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

  Future<void> _validateCode() async {
    if (!_codeFormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _validatedLinkCode = null;
      _validatedInstructorCode = null;
      _validatedInstructorAcademyId = null;
    });

    final raw = _codeController.text.trim().toUpperCase();

    try {
      // Dispatch by length: 6 = student linkCode, 8 = instructor invite.
      if (raw.length == 8) {
        final found = await validateInstructorCodeGlobally(raw);
        if (!mounted) return;
        if (found == null) {
          setState(() {
            _errorMessage = 'Codigo nao encontrado, expirado ou ja utilizado.';
            _isLoading = false;
          });
          return;
        }
        setState(() {
          _validatedInstructorCode = found.code;
          _validatedInstructorAcademyId = found.academyId;
          _currentStep = _Step.register;
          _isLoading = false;
        });
        return;
      }

      // Student flow (6 chars).
      final validation = await validateCodeGlobally(raw);

      if (!validation.valid) {
        if (!mounted) return;
        setState(() {
          _errorMessage = validation.error;
          _isLoading = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _validatedLinkCode = validation.linkCode;
        _currentStep = _Step.register;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erro ao validar codigo. Tente novamente.';
        _isLoading = false;
      });
    }
  }

  /// Instructor signup: creates the Firebase Auth user, writes the root
  /// `users/{uid}` doc, then calls [redeemInstructorCode] which links the
  /// user to the academy as `instructor` with extraPermissions and marks
  /// the invite as used.
  Future<void> _createInstructorAccount() async {
    if (_validatedInstructorCode == null ||
        _validatedInstructorAcademyId == null) return;
    if (_fullNameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Informe seu nome completo.');
      return;
    }
    if (_passwordController.text.length < 6) {
      setState(() => _errorMessage =
          'A senha deve ter pelo menos 6 caracteres.');
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'As senhas nao coincidem.');
      return;
    }
    if (_validatedInstructorCode!.isExpired) {
      setState(() {
        _errorMessage = 'Este codigo expirou. Solicite um novo.';
        _currentStep = _Step.code;
        _validatedInstructorCode = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentStep = _Step.creating;
    });

    try {
      final email = _emailController.text.trim();
      final displayName = _fullNameController.text.trim();
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: email,
        password: _passwordController.text,
      );
      final user = credential.user;
      if (user == null) throw Exception('No user returned from Firebase Auth');
      await user.updateDisplayName(displayName);

      // Root /users/{uid} doc + empty userAcademyMapping via service,
      // so linkUserToAcademy can safely update instead of creating from scratch.
      await globalUserService.createGlobalUser(
        userId: user.uid,
        email: email,
        displayName: displayName,
        accountType: AccountType.free,
      );

      await redeemInstructorCode(
        code: _validatedInstructorCode!,
        academyId: _validatedInstructorAcademyId!,
        userId: user.uid,
        userEmail: email,
        userDisplayName: displayName,
      );

      if (!mounted) return;
      setState(() {
        _currentStep = _Step.success;
        _isLoading = false;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _currentStep = _Step.register;
        _isLoading = false;
        _errorMessage = e.code == 'email-already-in-use'
            ? 'Email ja em uso. Faca login e use "Recebi codigo de equipe".'
            : 'Erro ao criar conta: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _currentStep = _Step.register;
        _isLoading = false;
        _errorMessage = 'Erro ao criar conta. Tente novamente.';
      });
    }
  }

  Future<void> _createAccount() async {
    if (!_registerFormKey.currentState!.validate()) return;
    if (_validatedLinkCode == null) return;

    // Re-validate code expiration before creating account
    // (code could have expired while user was filling the form)
    if (_validatedLinkCode!.expiresAt.isBefore(DateTime.now())) {
      setState(() {
        _errorMessage = 'Este codigo expirou. Solicite um novo codigo.';
        _currentStep = _Step.code;
        _validatedLinkCode = null;
      });
      return;
    }

    // Capture everything we need BEFORE any async operation.
    // The widget may be disposed during async work (GoRouter rebuilds on auth state change),
    // so we use the ProviderContainer directly instead of ref.
    final container = ProviderScope.containerOf(context);
    final authService = ref.read(authServiceProvider);
    final academyId = _validatedLinkCode!.academyId;
    final linkCodeService = LinkCodeService(academyId);
    final cpfDigits = _cpfController.text.replaceAll(RegExp(r'\D'), '');
    final phone = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final studentName = _validatedLinkCode!.studentName;
    final studentId = _validatedLinkCode!.studentId;
    final code = _validatedLinkCode!.code;

    // Show full-screen overlay (survives GoRouter rebuilds since it's in app.dart builder)
    container.read(creatingAccountStudentNameProvider.notifier).state = studentName;
    container.read(isCreatingAccountProvider.notifier).state = true;

    try {
      // Create Firebase account with the student name from the link code
      // This will also update the student document with linkedUserId and CPF
      final userCredential = await authService.createAccountWithLinkCode(
        email,
        password,
        studentName,
        studentId,
        academyId,
        cpfDigits.isNotEmpty ? cpfDigits : null,
        phone: phone.isNotEmpty ? phone : null,
      );

      // Mark the code as used
      await linkCodeService.markAsUsed(code, userCredential.user!.uid);

      // All Firestore documents are created. Force Riverpod to reload user data.
      container.invalidate(currentUserProvider);

      // Poll until currentUserProvider returns valid data with academy context (max 10 seconds)
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final userAsync = container.read(currentUserProvider);
        if (userAsync.hasValue && userAsync.value != null) {
          final user = userAsync.value!;
          // Make sure the user has academy context (not just a "free user" from the race condition)
          if (user.academyId != null) {
            break;
          }
          // Still showing as free user - invalidate and retry
          container.invalidate(currentUserProvider);
        }
        if (userAsync.hasError) {
          container.invalidate(currentUserProvider);
        }
      }

      // Dismiss overlay - the router will naturally redirect to the dashboard
      // since the user is authenticated and currentUserProvider has data
      container.read(isCreatingAccountProvider.notifier).state = false;
    } catch (e) {
      // Dismiss overlay on error
      container.read(isCreatingAccountProvider.notifier).state = false;

      if (mounted) {
        setState(() {
          _errorMessage = _getErrorMessage(e);
          _currentStep = _Step.register;
          _isLoading = false;
        });
      }
    }
  }

  String _getErrorMessage(dynamic error) {
    // Handle Firebase Auth errors with proper error codes
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'email-already-in-use':
          return 'Este email ja esta em uso';
        case 'invalid-email':
          return 'Email invalido';
        case 'weak-password':
          return 'Senha muito fraca. Use pelo menos 6 caracteres.';
        case 'operation-not-allowed':
          return 'Operacao nao permitida. Contate o suporte.';
        case 'network-request-failed':
          return 'Erro de conexao. Verifique sua internet.';
        default:
          debugPrint('Unhandled Firebase error: ${error.code} - ${error.message}');
          return 'Erro ao criar conta. Tente novamente.';
      }
    }

    // Handle FirebaseException (Firestore errors)
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'Erro de permissao. O codigo pode ter expirado.';
      }
      debugPrint('Firebase error: ${error.code} - ${error.message}');
      return 'Erro ao criar conta. Tente novamente.';
    }

    // Handle network errors
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('network') || errorStr.contains('socket')) {
      return 'Erro de conexao. Verifique sua internet.';
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
      case _Step.creating:
        return _buildCreatingStep();
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
            maxLength: 8,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
            ),
            decoration: const InputDecoration(
              labelText: 'Codigo',
              hintText: 'ABC123 ou ABCD2345',
              counterText: '',
              prefixIcon: Icon(LucideIcons.key, size: 20),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Informe o codigo';
              }
              // 6 = codigo de aluno, 8 = convite de professor.
              if (value.length != 6 && value.length != 8) {
                return 'O codigo deve ter 6 (aluno) ou 8 (professor) caracteres';
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
                        _isInstructorMode
                            ? 'Convite de ${_validatedInstructorCode!.createdByName}'
                            : 'Aluno: ${_validatedLinkCode!.studentName}',
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

          // Instructor: full name field (student name comes from linkCode)
          if (_isInstructorMode) ...[
            TextFormField(
              controller: _fullNameController,
              keyboardType: TextInputType.name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nome completo',
                prefixIcon: Icon(LucideIcons.user, size: 20),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe seu nome' : null,
            ).animate().fadeIn(delay: 350.ms).slideX(begin: -0.1),
            const SizedBox(height: 16),
          ] else ...[
            // CPF field (student only)
            TextFormField(
              controller: _cpfController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.\-]')),
                LengthLimitingTextInputFormatter(14),
              ],
              onChanged: (value) {
                final formatted = _formatCpf(value);
                if (formatted != _cpfController.text) {
                  _cpfController.value = TextEditingValue(
                    text: formatted,
                    selection: TextSelection.collapsed(offset: formatted.length),
                  );
                }
              },
              decoration: const InputDecoration(
                labelText: 'CPF',
                hintText: '000.000.000-00',
                prefixIcon: Icon(LucideIcons.fileText, size: 20),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Informe seu CPF';
                final digits = value.replaceAll(RegExp(r'\D'), '');
                if (digits.length != 11) return 'CPF deve ter 11 digitos';
                if (!_validateCpf(value)) return 'CPF invalido';
                return null;
              },
            ).animate().fadeIn(delay: 350.ms).slideX(begin: -0.1),
            const SizedBox(height: 16),
            // WhatsApp field (student only)
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              decoration: const InputDecoration(
                labelText: 'WhatsApp',
                hintText: '11999999999',
                prefixIcon: Icon(LucideIcons.phone, size: 20),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Informe seu WhatsApp';
                }
                final digits = value.replaceAll(RegExp(r'\D'), '');
                if (digits.length < 10) {
                  return 'WhatsApp deve ter pelo menos 10 digitos';
                }
                return null;
              },
            ).animate().fadeIn(delay: 375.ms).slideX(begin: -0.1),
            const SizedBox(height: 16),
          ],

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

          // Create account button (instructor uses dedicated handler)
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : (_isInstructorMode
                      ? _createInstructorAccount
                      : _createAccount),
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

  /// Shown briefly before the app-level overlay takes over
  Widget _buildCreatingStep() {
    return const Center(
      child: CircularProgressIndicator(),
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
          'Conta criada com sucesso!',
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

        const SizedBox(height: 16),

        Text(
          'Agora faca login para acessar o app',
          style: AppTheme.bodyMedium.copyWith(
            color: AppTheme.primary,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ).animate().fadeIn(delay: 250.ms),

        const SizedBox(height: 40),

        // Continue button
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: () => context.go('/login'),
            child: const Text('Ir para Login'),
          ),
        ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),
      ],
    );
  }
}
