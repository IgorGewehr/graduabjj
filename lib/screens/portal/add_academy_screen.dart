import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../providers/join_request_providers.dart';
import '../../providers/providers.dart';
import '../../providers/selected_academy_provider.dart';
import '../../providers/student_provider.dart';
import '../../services/firebase_service.dart';
import '../../services/link_code_service.dart';
import '../../services/team_service.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/polish/polish.dart';

/// Add Academy Screen
/// Allows user to link to a new academy using a 6-digit code
class AddAcademyScreen extends ConsumerStatefulWidget {
  const AddAcademyScreen({super.key});

  @override
  ConsumerState<AddAcademyScreen> createState() => _AddAcademyScreenState();
}

class _AddAcademyScreenState extends ConsumerState<AddAcademyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _codeFocusNode = FocusNode();

  bool _isLoading = false;
  bool _isValidating = false;
  String? _errorMessage;

  // Academy info after validation
  String? _academyId;
  String? _academyName;
  String? _academyLogoUrl;
  String? _studentName;
  bool _isAcademyJoinCodeMode = false;

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
        ),
        title: Text('Adicionar Academia', style: AppTheme.headlineSmall),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.divider),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Instructions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.infoLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      LucideIcons.info,
                      size: 20,
                      color: AppTheme.info,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Codigo de Vinculacao',
                            style: AppTheme.titleSmall.copyWith(
                              color: AppTheme.info,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Solicite um codigo de 6 digitos a sua academia para vincular sua conta.',
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.info,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Code input section
              if (_academyId == null) ...[
                Text('Digite o codigo', style: AppTheme.titleMedium),
                const SizedBox(height: 8),

                // Code input
                TextFormField(
                  controller: _codeController,
                  focusNode: _codeFocusNode,
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                    UpperCaseTextFormatter(),
                  ],
                  style: AppTheme.headlineMedium.copyWith(
                    letterSpacing: 8,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: '------',
                    hintStyle: AppTheme.headlineMedium.copyWith(
                      letterSpacing: 8,
                      color: AppTheme.textDisabled,
                    ),
                    counterText: '',
                    errorText: _errorMessage,
                    prefixIcon: _isValidating
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _errorMessage = null;
                    });
                    if (value.length == 6) {
                      _validateCode(value);
                    }
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Digite o codigo';
                    }
                    if (value.length != 6) {
                      return 'O codigo deve ter 6 digitos';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 24),

                // Validate button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isValidating ? null : _onValidatePressed,
                    child: _isValidating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Validar Codigo'),
                  ),
                ),
              ],

              // Academy confirmation section
              if (_academyId != null) ...[_buildAcademyConfirmation()],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAcademyConfirmation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Success icon
        const Center(child: SuccessCheck(size: 64)),
        const SizedBox(height: 16),

        Center(child: Text('Codigo Valido!', style: AppTheme.headlineSmall)),
        const SizedBox(height: 24),

        // Academy card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              // Logo
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _academyLogoUrl == null ? AppTheme.primary : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                clipBehavior: Clip.antiAlias,
                child: _academyLogoUrl != null
                    ? AppCachedImage(
                        imageUrl: _academyLogoUrl,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorIcon: _buildDefaultLogo(),
                      )
                    : _buildDefaultLogo(),
              ),
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _academyName ?? 'Academia',
                      style: AppTheme.titleMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_studentName != null) ...[
                      const SizedBox(height: 4),
                      Text('Aluno: $_studentName', style: AppTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Warning
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.warningLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                LucideIcons.alertTriangle,
                size: 18,
                color: AppTheme.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ao confirmar, voce tera acesso aos dados desta academia e podera alternar entre suas academias.',
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.warning),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Actions
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isLoading ? null : _resetForm,
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading ? null : _linkToAcademy,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Confirmar'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDefaultLogo() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          _academyName?.isNotEmpty == true
              ? _academyName![0].toUpperCase()
              : 'A',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  void _onValidatePressed() {
    if (_formKey.currentState?.validate() ?? false) {
      _validateCode(_codeController.text);
    }
  }

  Future<void> _validateCode(String code) async {
    setState(() {
      _isValidating = true;
      _errorMessage = null;
    });

    final raw = code.trim().toUpperCase();

    try {
      // 1. Tenta o código ÚNICO da academia (multi-uso - ilimitado)
      Map<String, dynamic>? acad;
      try {
        acad = await teamService.resolveAcademyCode(raw);
      } catch (_) {
        try {
          await Future.delayed(const Duration(milliseconds: 350));
          acad = await teamService.resolveAcademyCode(raw);
        } catch (_) {}
      }

      if (!mounted) return;
      if (acad != null && acad['found'] == true) {
        final foundAcademyId = acad['academyId']?.toString() ?? '';
        final mapping = ref.read(userAcademyMappingProvider).valueOrNull;
        if (mapping?.academyIds.contains(foundAcademyId) == true) {
          setState(() {
            _isValidating = false;
            _errorMessage = 'Você já está vinculado a esta academia.';
          });
          return;
        }

        setState(() {
          _isValidating = false;
          _academyId = foundAcademyId;
          _academyName = acad!['academyName']?.toString() ?? 'Academia';
          _academyLogoUrl = null;
          _studentName = null;
          _isAcademyJoinCodeMode = true;
        });
        return;
      }

      // 2. Se não for código de academia, tenta o código de aluno legado
      final validation = await validateCodeGlobally(raw);
      if (validation.valid && validation.linkCode != null) {
        final linkCode = validation.linkCode!;
        final foundAcademyId = linkCode.academyId;

        final mapping = ref.read(userAcademyMappingProvider).valueOrNull;
        if (mapping?.academyIds.contains(foundAcademyId) == true) {
          setState(() {
            _isValidating = false;
            _errorMessage = 'Você já está vinculado a esta academia.';
          });
          return;
        }

        String academyName = 'Academia';
        String? academyLogoUrl;
        try {
          final academyDoc = await FirebaseService.firestore
              .collection('academies')
              .doc(foundAcademyId)
              .get();
          academyName = academyDoc.data()?['name'] ?? 'Academia';
          academyLogoUrl = academyDoc.data()?['logoUrl'];
        } catch (_) {}

        setState(() {
          _isValidating = false;
          _academyId = foundAcademyId;
          _academyName = academyName;
          _academyLogoUrl = academyLogoUrl;
          _studentName =
              linkCode.studentName.isNotEmpty ? linkCode.studentName : null;
          _isAcademyJoinCodeMode = false;
        });
        return;
      }

      setState(() {
        _isValidating = false;
        _errorMessage =
            'Código não encontrado. Verifique se digitou os 6 caracteres corretamente.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isValidating = false;
        _errorMessage = 'Erro ao validar código. Tente novamente.';
      });
    }
  }

  void _resetForm() {
    setState(() {
      _codeController.clear();
      _academyId = null;
      _academyName = null;
      _academyLogoUrl = null;
      _studentName = null;
      _isAcademyJoinCodeMode = false;
      _errorMessage = null;
    });
    _codeFocusNode.requestFocus();
  }

  Future<void> _linkToAcademy() async {
    if (_academyId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final code = _codeController.text.trim().toUpperCase();
      if (_isAcademyJoinCodeMode) {
        await teamService.submitJoinRequest(code);
        ref.invalidate(pendingJoinRequestProvider);
        ref.invalidate(currentUserProvider);
        ref.invalidate(currentStudentProvider);

        if (mounted) {
          Celebration.confetti(context);
          FeedbackUtils.showSuccess(
            context,
            'Solicitação enviada para $_academyName! Aguardando aprovação do mestre.',
          );
          context.pop();
        }
      } else {
        final authService = ref.read(authServiceProvider);
        await authService.linkStudentAccount(
          code,
          _academyId!,
        );

        // Refresh providers
        ref.invalidate(userAcademiesInfoProvider);
        ref.invalidate(userAcademyMappingProvider);
        await ref.read(selectedAcademyProvider.notifier).refreshAcademyCache();

        if (mounted) {
          Celebration.confetti(context);
          FeedbackUtils.showSuccess(
            context,
            'Vinculado a $_academyName com sucesso!',
          );
          context.pop();
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        FeedbackUtils.showError(
          context,
          e.toString().replaceAll('Exception: ', ''),
        );
      }
    }
  }
}

/// Formatter to convert text to uppercase
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
