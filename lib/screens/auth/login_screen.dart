import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';

// =============================================================================
// Paleta FIGHTER — bone + ink + um acento vermelho. Espelha _C das telas
// lib/screens/fighter/* (lutador_hub / cena). Só apresentação: nenhuma
// regra de negócio, controller ou navegação muda por causa disso.
// =============================================================================
class _C {
  _C._();
  static const bone = Color(0xFFF4F3EF);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF0A0A0A);
  static const blood = Color(0xFFB91C1C);
  static const smoke = Color(0xFF6E6E68);
  static const ash = Color(0xFF9A9A93);
}

TextStyle _eyebrow(Color c, double s) => TextStyle(
    color: c, fontSize: s, fontWeight: FontWeight.w800, letterSpacing: 1.4);

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

  // ── Decoração FIGHTER dos campos: fill ink@4%, hairline, foco vermelho ─────
  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
          color: _C.ash, fontSize: 15, fontWeight: FontWeight.w600),
      prefixIcon: Icon(icon, size: 20, color: _C.smoke),
      suffixIcon: suffix,
      filled: true,
      fillColor: _C.ink.withValues(alpha: 0.04),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      enabledBorder: border(_C.ink.withValues(alpha: 0.10), 1),
      border: border(_C.ink.withValues(alpha: 0.10), 1),
      focusedBorder: border(_C.blood, 1.6),
      errorBorder: border(_C.blood.withValues(alpha: 0.7), 1),
      focusedErrorBorder: border(_C.blood, 1.6),
      errorStyle: const TextStyle(
          color: _C.blood, fontSize: 12.5, fontWeight: FontWeight.w600),
    );
  }

  // ── Link discreto em vermelho (esqueci senha / criar conta / instrutor) ────
  Widget _redLink(String label, VoidCallback onTap, {double size = 14}) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: _C.blood,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: TextStyle(
            color: _C.blood, fontSize: size, fontWeight: FontWeight.w800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bone,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo da marca
                  Center(
                    child: Image.asset(
                      'assets/images/mydojo_logo_horizontal.png',
                      width: 260,
                      height: 78,
                      fit: BoxFit.contain,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Error message
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _C.blood.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _C.blood.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            LucideIcons.alertCircle,
                            color: _C.blood,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: _C.blood,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Label EMAIL
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 8),
                    child: Text('EMAIL', style: _eyebrow(_C.ink, 11)),
                  ),

                  // Email field
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(
                        color: _C.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                    decoration: _fieldDecoration(
                      hint: 'voce@email.com',
                      icon: LucideIcons.mail,
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
                  ),

                  const SizedBox(height: 18),

                  // Label SENHA
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 8),
                    child: Text('SENHA', style: _eyebrow(_C.ink, 11)),
                  ),

                  // Password field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _handleLogin(),
                    style: const TextStyle(
                        color: _C.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                    decoration: _fieldDecoration(
                      hint: '••••••••',
                      icon: LucideIcons.lock,
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? LucideIcons.eyeOff
                              : LucideIcons.eye,
                          size: 20,
                          color: _C.smoke,
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
                  ),

                  const SizedBox(height: 6),

                  // Forgot password
                  Align(
                    alignment: Alignment.centerRight,
                    child: _redLink(
                        'Esqueci minha senha', _handleForgotPassword),
                  ),

                  const SizedBox(height: 18),

                  // Login button — CTA INK all-caps. Preserva _isLoading e
                  // _handleLogin (desabilita o toque durante o loading).
                  GestureDetector(
                    onTap: _isLoading ? null : _handleLogin,
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: _C.ink,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'ENTRAR',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Register link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Nao tem uma conta? ',
                        style: TextStyle(
                          color: _C.smoke,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      _redLink('Criar academia', () => context.go('/register')),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // Divider
                  Row(
                    children: [
                      Expanded(
                        child: Divider(
                            color: _C.ink.withValues(alpha: 0.10),
                            thickness: 1),
                      ),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14),
                        child: Text('OU', style: _eyebrow(_C.ash, 11)),
                      ),
                      Expanded(
                        child: Divider(
                            color: _C.ink.withValues(alpha: 0.10),
                            thickness: 1),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // Link Code Button — secundário outline
                  GestureDetector(
                    onTap: () => context.go('/link-code'),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: _C.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _C.ink.withValues(alpha: 0.14)),
                      ),
                      alignment: Alignment.center,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.key, size: 18, color: _C.ink),
                          SizedBox(width: 10),
                          Text(
                            'TENHO UM CODIGO DE ACESSO',
                            style: TextStyle(
                              color: _C.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  Center(
                    // O fluxo /link-code já detecta código de 8 chars e entra
                    // no modo instrutor (cria conta + resgata o convite). O
                    // /codigo-equipe exige usuário logado e era barrado pelo
                    // redirect na tela de login.
                    child: _redLink(
                      'Recebi codigo de equipe (instrutor)',
                      () => context.go('/link-code'),
                      size: 13,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Legal links
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () => _openUrl(AppConstants.termsOfServiceUrl),
                        child: const Text(
                          'Termos de Uso',
                          style: TextStyle(
                            color: _C.ash,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      const Text(
                        '   ·   ',
                        style: TextStyle(
                          color: _C.ash,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _openUrl(AppConstants.privacyPolicyUrl),
                        child: const Text(
                          'Politica de Privacidade',
                          style: TextStyle(
                            color: _C.ash,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
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
                Icon(
                  LucideIcons.checkCircle,
                  color: AppTheme.success,
                  size: 36,
                ),
                const SizedBox(height: 12),
                Text(
                  'Enviamos um link de recuperacao para ${_emailController.text.trim()}.',
                  style: AppTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Verifique tambem sua caixa de spam.',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
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
                onPressed: _isSending
                    ? null
                    : () => Navigator.of(context).pop(),
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
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text('Enviar'),
              ),
            ],
    );
  }
}
