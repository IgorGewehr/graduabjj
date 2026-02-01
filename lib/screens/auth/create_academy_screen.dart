import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';

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
  final _slugController = TextEditingController();
  bool _slugManuallyEdited = false;

  // Slug availability
  bool? _slugAvailable;
  bool _checkingSlug = false;
  Timer? _slugDebounceTimer;

  // General state
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _academyNameController.dispose();
    _slugController.dispose();
    _slugDebounceTimer?.cancel();
    super.dispose();
  }

  // ============================================
  // Slug Generation
  // ============================================
  String _generateSlug(String name) {
    // Remove accents
    const accents = 'ÀÁÂÃÄÅàáâãäåÒÓÔÕÖØòóôõöøÈÉÊËèéêëÇçÌÍÎÏìíîïÙÚÛÜùúûüÿÑñ';
    const noAccents = 'AAAAAAaaaaaaOOOOOOooooooEEEEeeeeCcIIIIiiiiUUUUuuuuyNn';

    var slug = name.toLowerCase();
    for (var i = 0; i < accents.length; i++) {
      slug = slug.replaceAll(accents[i], noAccents[i]);
    }

    return slug
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  void _onAcademyNameChanged(String value) {
    if (!_slugManuallyEdited) {
      final slug = _generateSlug(value);
      _slugController.text = slug;
      _checkSlugAvailability(slug);
    }
  }

  void _onSlugChanged(String value) {
    _slugManuallyEdited = true;
    final slug = _generateSlug(value);
    if (slug != value) {
      _slugController.text = slug;
      _slugController.selection = TextSelection.fromPosition(
        TextPosition(offset: slug.length),
      );
    }
    _checkSlugAvailability(slug);
  }

  void _checkSlugAvailability(String slug) {
    _slugDebounceTimer?.cancel();
    setState(() {
      _slugAvailable = null;
      _checkingSlug = false;
    });

    if (slug.length < 3) return;

    setState(() => _checkingSlug = true);

    _slugDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('academies')
            .doc(slug)
            .get();

        if (mounted) {
          setState(() {
            _slugAvailable = !doc.exists;
            _checkingSlug = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _slugAvailable = null;
            _checkingSlug = false;
          });
        }
      }
    });
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

      if (_slugAvailable == false) {
        setState(() {
          _errorMessage = 'Este identificador ja esta em uso. Escolha outro.';
        });
        return;
      }
      if (_slugAvailable == null && _slugController.text.length >= 3) {
        setState(() {
          _errorMessage = 'Aguarde a verificacao do identificador.';
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

    try {
      final slug = _slugController.text.trim();

      // Double-check slug availability
      final slugDoc = await FirebaseFirestore.instance
          .collection('academies')
          .doc(slug)
          .get();

      if (slugDoc.exists) {
        setState(() {
          _errorMessage = 'Este identificador ja esta em uso. Escolha outro.';
          _slugAvailable = false;
          _isLoading = false;
        });
        return;
      }

      final authService = ref.read(authServiceProvider);
      await authService.createAcademyAccount(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _nameController.text.trim(),
        academyName: _academyNameController.text.trim(),
        academySlug: slug,
      );

      // Success - go to step 3
      _goToStep(2);
    } catch (e) {
      setState(() {
        _errorMessage = _getErrorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getErrorMessage(dynamic error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('email-already-in-use')) {
      return 'Este email ja esta em uso. Faca login ou use outro email.';
    } else if (msg.contains('invalid-email')) {
      return 'Email invalido';
    } else if (msg.contains('weak-password')) {
      return 'Senha muito fraca. Use pelo menos 6 caracteres.';
    } else if (msg.contains('permission-denied') || msg.contains('permission denied')) {
      return 'Erro de permissao. Entre em contato com o suporte.';
    } else if (msg.contains('network')) {
      return 'Erro de conexao. Verifique sua internet.';
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
            // Icon
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF667EEA).withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(LucideIcons.user, size: 32, color: Colors.white),
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
                if (!value.contains('@')) return 'Email invalido';
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
                hintText: 'Minimo 6 caracteres',
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
                if (value != _passwordController.text) return 'As senhas nao coincidem';
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
                  'Ja tem uma conta? ',
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
            // Icon
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF093FB), Color(0xFFF5576C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF5576C).withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(LucideIcons.building2, size: 32, color: Colors.white),
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
              onChanged: _onAcademyNameChanged,
              validator: (value) {
                if (value == null || value.isEmpty) return 'Informe o nome da academia';
                if (value.trim().length < 3) return 'Nome deve ter pelo menos 3 caracteres';
                return null;
              },
            ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.1),

            const SizedBox(height: 16),

            // Slug field with availability indicator
            TextFormField(
              controller: _slugController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _handleNext(),
              decoration: InputDecoration(
                labelText: 'Identificador (URL)',
                hintText: 'team-alpha',
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  child: Text('/', style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary)),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                suffixIcon: _buildSlugSuffix(),
                helperText: _getSlugHelperText(),
                helperStyle: TextStyle(
                  color: _slugAvailable == true
                      ? AppTheme.success
                      : _slugAvailable == false
                          ? AppTheme.error
                          : AppTheme.textSecondary,
                ),
                errorText: _slugAvailable == false ? 'Identificador ja em uso' : null,
              ),
              onChanged: _onSlugChanged,
              validator: (value) {
                if (value == null || value.isEmpty) return 'Informe o identificador';
                if (value.length < 3) return 'Minimo 3 caracteres';
                return null;
              },
            ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.1),

            const SizedBox(height: 24),

            // Feature chips
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.sparkles, size: 16, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 6),
                      Text(
                        'Incluso no plano gratuito (30 dias):',
                        style: AppTheme.titleSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _FeatureChip(icon: LucideIcons.users, label: 'Ate 30 alunos'),
                      _FeatureChip(icon: LucideIcons.calendar, label: 'Controle de presenca'),
                      _FeatureChip(icon: LucideIcons.graduationCap, label: 'Graduacao'),
                      _FeatureChip(icon: LucideIcons.barChart3, label: 'Relatorios'),
                      _FeatureChip(icon: LucideIcons.shield, label: 'Painel admin'),
                    ],
                  ),
                ],
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

  Widget? _buildSlugSuffix() {
    if (_slugController.text.length < 3) return null;
    if (_checkingSlug) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_slugAvailable == true) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Icon(LucideIcons.checkCircle, size: 20, color: AppTheme.success),
      );
    }
    if (_slugAvailable == false) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Icon(LucideIcons.xCircle, size: 20, color: AppTheme.error),
      );
    }
    return null;
  }

  String _getSlugHelperText() {
    final slug = _slugController.text;
    if (slug.length < 3) return 'Identificador unico (minimo 3 caracteres)';
    if (_checkingSlug) return 'Verificando disponibilidade...';
    if (_slugAvailable == true) return 'Disponivel! URL: bjjeasy.com.br/$slug';
    if (_slugAvailable == false) return 'Ja em uso. Escolha outro.';
    return 'URL: bjjeasy.com.br/$slug';
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
                  color: const Color(0xFF43E97B).withOpacity(0.3),
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
                const TextSpan(text: ' esta pronta para uso.'),
              ],
            ),
          ).animate().fadeIn(delay: 400.ms),

          const SizedBox(height: 28),

          // URL chip
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.successLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.success.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                Text(
                  'Seu painel de administracao:',
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'bjjeasy.com.br/${_slugController.text}',
                    style: AppTheme.labelLarge.copyWith(
                      color: Colors.white,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.1),

          const SizedBox(height: 40),

          // Access button
          SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.go('/admin'),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.sparkles, size: 18),
                  const SizedBox(width: 8),
                  const Text('Acessar Meu Painel'),
                ],
              ),
            ),
          ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.1),

          const SizedBox(height: 12),

          Text(
            'Voce sera redirecionado para o dashboard',
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
        border: Border.all(color: AppTheme.error.withOpacity(0.3)),
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

/// Feature chip widget
class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(label, style: AppTheme.bodySmall),
        ],
      ),
    );
  }
}
