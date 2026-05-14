import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';

/// Login Screen
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.signInWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );
      // Navigation is handled by router redirect
    } catch (e) {
      setState(() {
        _errorMessage = _getErrorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _getErrorMessage(dynamic error) {
    if (error.toString().contains('user-not-found')) {
      return 'Usuario nao encontrado';
    } else if (error.toString().contains('wrong-password')) {
      return 'Senha incorreta';
    } else if (error.toString().contains('invalid-email')) {
      return 'Email invalido';
    } else if (error.toString().contains('too-many-requests')) {
      return 'Muitas tentativas. Tente novamente mais tarde.';
    }
    return 'Erro ao fazer login. Tente novamente.';
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _handleForgotPassword() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ForgotPasswordDialog(
        initialEmail: _emailController.text.trim(),
        onSubmit: (email) async {
          final authService = ref.read(authServiceProvider);
          await authService.resetPassword(email);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo
                  Image.asset(
                    'assets/images/bjjeasy_logo.png',
                    width: 180,
                    height: 180,
                  ).animate().fadeIn(duration: 300.ms).scale(
                        begin: const Offset(0.8, 0.8),
                      ),

                  const SizedBox(height: 40),

                  // Error message
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.errorLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.error.withOpacity(0.3)),
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

                  // Email field
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: 'Email',
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
                  ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.1),

                  const SizedBox(height: 16),

                  // Password field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _handleLogin(),
                    decoration: InputDecoration(
                      hintText: 'Senha',
                      prefixIcon: const Icon(LucideIcons.lock, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? LucideIcons.eyeOff
                              : LucideIcons.eye,
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
                        return 'Informe sua senha';
                      }
                      return null;
                    },
                  ).animate().fadeIn(delay: 400.ms).slideX(begin: -0.1),

                  const SizedBox(height: 12),

                  // Forgot password
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _handleForgotPassword,
                      child: Text(
                        'Esqueci minha senha',
                        style: AppTheme.labelMedium.copyWith(
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ).animate().fadeIn(delay: 500.ms),

                  const SizedBox(height: 24),

                  // Login button
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Entrar'),
                    ),
                  ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.1),

                  const SizedBox(height: 24),

                  // Register link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Nao tem uma conta? ',
                        style: AppTheme.bodyMedium.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.go('/register'),
                        child: const Text('Criar conta'),
                      ),
                    ],
                  ).animate().fadeIn(delay: 700.ms),

                  const SizedBox(height: 16),

                  // Divider
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'ou',
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ).animate().fadeIn(delay: 800.ms),

                  const SizedBox(height: 16),

                  // Link Code Button
                  OutlinedButton.icon(
                    onPressed: () => context.go('/link-code'),
                    icon: const Icon(LucideIcons.key, size: 18),
                    label: const Text('Tenho um codigo de acesso'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ).animate().fadeIn(delay: 900.ms),

                  const SizedBox(height: 8),

                  TextButton(
                    onPressed: () => context.push('/codigo-equipe'),
                    child: Text(
                      'Recebi codigo de equipe (instrutor)',
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ).animate().fadeIn(delay: 950.ms),

                  const SizedBox(height: 24),

                  // Legal links
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () => _openUrl(AppConstants.termsOfServiceUrl),
                        child: Text(
                          'Termos de Uso',
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textSecondary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      Text(
                        '  |  ',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _openUrl(AppConstants.privacyPolicyUrl),
                        child: Text(
                          'Politica de Privacidade',
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textSecondary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 1000.ms),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Modal dedicated to the "forgot password" flow.
///
/// Replaces the previous snackbar-based flow where the user could miss the
/// feedback (snackbars time out after a few seconds and the original
/// implementation also bailed silently when the email field was empty).
/// Here the user sees a clear loading state, gets a confirmation screen on
/// success, and any Firebase error is shown inside the dialog itself.
class _ForgotPasswordDialog extends StatefulWidget {
  final String initialEmail;
  final Future<void> Function(String email) onSubmit;

  const _ForgotPasswordDialog({
    required this.initialEmail,
    required this.onSubmit,
  });

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _emailController;
  bool _isSending = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Digite um email válido.');
      return;
    }
    setState(() {
      _isSending = true;
      _error = null;
    });
    try {
      await widget.onSubmit(email);
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _sent = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _error = _mapAuthError(e);
      });
    }
  }

  String _mapAuthError(Object e) {
    final s = e.toString();
    if (s.contains('user-not-found')) {
      return 'Email nao cadastrado.';
    }
    if (s.contains('invalid-email')) {
      return 'Email invalido.';
    }
    if (s.contains('too-many-requests')) {
      return 'Muitas tentativas. Tente novamente em alguns minutos.';
    }
    return 'Erro ao enviar email. Tente novamente.';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_sent ? 'Email enviado' : 'Recuperar senha'),
      content: _sent
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.checkCircle,
                    color: AppTheme.success, size: 36),
                const SizedBox(height: 12),
                Text(
                  'Enviamos um link de recuperacao para ${_emailController.text.trim()}.',
                  style: AppTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Verifique tambem sua caixa de spam.',
                  style: AppTheme.labelSmall
                      .copyWith(color: AppTheme.textSecondary),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Digite seu email cadastrado. Enviaremos um link para criar uma nova senha.',
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  enabled: !_isSending,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(LucideIcons.mail, size: 18),
                    errorText: _error,
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ],
            ),
      actions: _sent
          ? [
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ]
          : [
              TextButton(
                onPressed:
                    _isSending ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: _isSending ? null : _submit,
                child: _isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Enviar'),
              ),
            ],
    );
  }
}
