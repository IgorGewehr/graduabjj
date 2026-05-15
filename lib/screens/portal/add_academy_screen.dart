import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../providers/providers.dart';
import '../../services/firebase_service.dart';
import '../../widgets/cached_image.dart';

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
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.successLight,
              borderRadius: BorderRadius.circular(32),
            ),
            child: const Icon(
              LucideIcons.checkCircle,
              size: 32,
              color: AppTheme.success,
            ),
          ),
        ),
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

    try {
      final firestore = FirebaseService.firestore;

      // Search for the code in all academies' linkCodes subcollection
      final academiesSnapshot = await firestore.collection('academies').get();

      String? foundAcademyId;
      String? foundStudentId;
      Map<String, dynamic>? codeData;

      for (final academyDoc in academiesSnapshot.docs) {
        final codeQuery = await academyDoc.reference
            .collection('linkCodes')
            .where('code', isEqualTo: code.toUpperCase())
            .where('usedAt', isNull: true)
            .limit(1)
            .get();

        if (codeQuery.docs.isNotEmpty) {
          foundAcademyId = academyDoc.id;
          codeData = codeQuery.docs.first.data();
          foundStudentId = codeData['studentId'] as String?;
          break;
        }
      }

      if (foundAcademyId == null || codeData == null) {
        setState(() {
          _isValidating = false;
          _errorMessage = 'Codigo invalido ou ja utilizado';
        });
        return;
      }

      // Check if code is expired
      final expiresAt = (codeData['expiresAt'] as Timestamp?)?.toDate();
      if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
        setState(() {
          _isValidating = false;
          _errorMessage = 'Codigo expirado';
        });
        return;
      }

      // Check if already linked to this academy
      final mapping = ref.read(userAcademyMappingProvider).valueOrNull;
      if (mapping?.academyIds.contains(foundAcademyId) == true) {
        setState(() {
          _isValidating = false;
          _errorMessage = 'Voce ja esta vinculado a esta academia';
        });
        return;
      }

      // Get academy info
      final academyDoc = await firestore
          .collection('academies')
          .doc(foundAcademyId)
          .get();
      final academyData = academyDoc.data();

      // Get student info if available
      String? studentName;
      if (foundStudentId != null) {
        final studentDoc = await firestore
            .collection('academies/$foundAcademyId/students')
            .doc(foundStudentId)
            .get();
        if (studentDoc.exists) {
          studentName = studentDoc.data()?['fullName'] as String?;
        }
      }

      setState(() {
        _isValidating = false;
        _academyId = foundAcademyId;
        _academyName = academyData?['name'] ?? 'Academia';
        _academyLogoUrl = academyData?['logoUrl'];
        _studentName = studentName;
      });
    } catch (e) {
      setState(() {
        _isValidating = false;
        _errorMessage = 'Erro ao validar codigo. Tente novamente.';
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
      final authService = ref.read(authServiceProvider);
      await authService.linkStudentAccount(
        _codeController.text.toUpperCase(),
        _academyId!,
      );

      // Refresh providers
      ref.invalidate(userAcademiesInfoProvider);
      ref.invalidate(userAcademyMappingProvider);
      await ref.read(selectedAcademyProvider.notifier).refreshAcademyCache();

      if (mounted) {
        FeedbackUtils.showSuccess(
          context,
          'Vinculado a $_academyName com sucesso!',
        );
        context.pop();
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
