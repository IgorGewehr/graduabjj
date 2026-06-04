import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../providers/totp_provider.dart';
import '../../widgets/polish/polish.dart';

/// TOTP 2FA Setup Screen
/// 3-step flow: QR code → Verify code → Backup codes
class TotpSetupScreen extends ConsumerStatefulWidget {
  const TotpSetupScreen({super.key});

  @override
  ConsumerState<TotpSetupScreen> createState() => _TotpSetupScreenState();
}

class _TotpSetupScreenState extends ConsumerState<TotpSetupScreen> {
  int _currentStep = 0; // 0=QR, 1=Verify, 2=Backup
  bool _isLoading = true;
  String? _secret;
  String? _qrCodeUri;
  List<String>? _backupCodes;
  String? _errorMessage;

  final _codeController = TextEditingController();
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _startSetup();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _startSetup() async {
    final service = ref.read(totpServiceProvider);
    final result = await service.setupTotp();

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result.success) {
        _secret = result.secret;
        _qrCodeUri = result.qrCodeUri;
      } else {
        _errorMessage = result.message ?? 'Erro ao iniciar configuracao';
      }
    });
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Digite o codigo de 6 digitos');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    final service = ref.read(totpServiceProvider);
    final result = await service.verifySetup(code);

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _isVerifying = false;
        _backupCodes = result.backupCodes;
        _currentStep = 2;
      });
      // Genuine win: 2FA successfully enabled.
      Celebration.confetti(context);
    } else {
      setState(() {
        _isVerifying = false;
        _errorMessage = result.message ?? 'Codigo invalido';
      });
    }
  }

  void _finish() {
    ref.invalidate(totpEnabledProvider);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Configurar 2FA'),
        backgroundColor: AppTheme.background,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Gerando chave de seguranca...',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              )
            : _errorMessage != null && _currentStep == 0 && _qrCodeUri == null
                ? _buildError()
                : _buildStepContent(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.alertCircle,
                size: 48,
                color: AppTheme.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _errorMessage!,
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
                _startSetup();
              },
              icon: const Icon(LucideIcons.refreshCw),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step indicator
          _buildStepIndicator(),
          const SizedBox(height: 32),

          // Step content
          if (_currentStep == 0) _buildStep1QrCode().entrance(),
          if (_currentStep == 1) _buildStep2Verify().entrance(),
          if (_currentStep == 2) _buildStep3BackupCodes().entrance(),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      children: List.generate(3, (index) {
        final isActive = index == _currentStep;
        final isCompleted = index < _currentStep;
        return Expanded(
          child: Row(
            children: [
              if (index > 0)
                Expanded(
                  child: Container(
                    height: 2,
                    color: isCompleted || isActive
                        ? AppTheme.primary
                        : AppTheme.divider,
                  ),
                ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted
                      ? AppTheme.primary
                      : isActive
                          ? AppTheme.primary
                          : AppTheme.surfaceVariant,
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(LucideIcons.check,
                          size: 16, color: Colors.white)
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: isActive ? Colors.white : AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                ),
              ),
              if (index < 2 && index == 0)
                Expanded(
                  child: Container(
                    height: 2,
                    color: _currentStep > 0 ? AppTheme.primary : AppTheme.divider,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildStep1QrCode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Escaneie o QR Code',
          style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Abra o Google Authenticator (ou outro app TOTP) e escaneie o codigo abaixo.',
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 24),

        // QR Code
        if (_qrCodeUri != null)
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.divider),
              ),
              child: QrImageView(
                data: _qrCodeUri!,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
          ),

        const SizedBox(height: 24),

        // Manual secret
        if (_secret != null) ...[
          Text(
            'Ou insira o codigo manualmente:',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _secret!,
                    style: AppTheme.bodyMedium.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.copy, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _secret!));
                    context.showSuccess('Codigo copiado!');
                  },
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 32),

        // Next button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => setState(() => _currentStep = 1),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Proximo'),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2Verify() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Verifique o codigo',
          style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Digite o codigo de 6 digitos exibido no seu aplicativo autenticador.',
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 24),

        // Error
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.errorLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.alertCircle,
                    color: AppTheme.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.error),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Code input
        TextFormField(
          controller: _codeController,
          decoration: const InputDecoration(
            labelText: 'Codigo de verificacao',
            hintText: '000000',
            prefixIcon: Icon(LucideIcons.keyRound),
          ),
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: AppTheme.headlineSmall.copyWith(
            letterSpacing: 8,
            fontWeight: FontWeight.w700,
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onFieldSubmitted: (_) => _verifyCode(),
        ),

        const SizedBox(height: 24),

        // Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() {
                  _currentStep = 0;
                  _errorMessage = null;
                }),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Voltar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _isVerifying ? null : _verifyCode,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isVerifying
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Verificar'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep3BackupCodes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: const SuccessCheck()),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF16A34A).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.shieldCheck,
                  color: Color(0xFF16A34A), size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '2FA ativado com sucesso!',
                  style: AppTheme.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF16A34A),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Text(
          'Codigos de recuperacao',
          style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Salve esses codigos em um local seguro. Cada codigo so pode ser usado uma vez caso voce perca acesso ao seu autenticador.',
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 16),

        // Backup codes grid
        if (_backupCodes != null && _backupCodes!.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: _backupCodes!
                      .map((code) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.divider),
                            ),
                            child: Text(
                              code,
                              style: AppTheme.bodyMedium.copyWith(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final text = _backupCodes!.join('\n');
                      Clipboard.setData(ClipboardData(text: text));
                      context.showSuccess('Codigos copiados!');
                    },
                    icon: const Icon(LucideIcons.copy, size: 18),
                    label: const Text('Copiar todos'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 32),

        // Finish button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _finish,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Concluir'),
          ),
        ),
      ],
    );
  }
}
