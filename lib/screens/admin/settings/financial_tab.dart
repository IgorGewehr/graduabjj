import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme.dart';
import '../../../services/services.dart';
import 'settings_shared_widgets.dart';

/// Content for the "Financeiro" settings tab (PIX, payment gateways, KYC).
class FinancialTab extends StatelessWidget {
  final TextEditingController pixKeyController;
  final PixKeyType? pixKeyType;
  final ValueChanged<PixKeyType?> onPixKeyTypeChanged;
  final bool abacatePayEnabled;
  final ValueChanged<bool> onAbacatePayChanged;
  final bool asaasEnabled;

  // KYC
  final String kycStatus;
  final String? kycOnboardingUrl;
  final bool isCheckingKyc;
  final VoidCallback onCheckKyc;

  const FinancialTab({
    super.key,
    required this.pixKeyController,
    required this.pixKeyType,
    required this.onPixKeyTypeChanged,
    required this.abacatePayEnabled,
    required this.onAbacatePayChanged,
    required this.asaasEnabled,
    required this.kycStatus,
    required this.kycOnboardingUrl,
    required this.isCheckingKyc,
    required this.onCheckKyc,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        key: const ValueKey('financial'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // PIX Settings
          SettingsCard(
            title: 'Chave PIX',
            icon: LucideIcons.qrCode,
            child: Column(
              children: [
                ModernTextField(
                  controller: pixKeyController,
                  label: 'Chave PIX',
                  hint: 'Sua chave PIX',
                  icon: LucideIcons.key,
                ),
                const SizedBox(height: 16),
                ModernDropdown<PixKeyType>(
                  label: 'Tipo da Chave',
                  value: pixKeyType,
                  items: PixKeyType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type.label),
                    );
                  }).toList(),
                  onChanged: onPixKeyTypeChanged,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Payment integrations
          SettingsCard(
            title: 'Integracoes',
            icon: LucideIcons.plug,
            child: Column(
              children: [
                ModernSwitch(
                  title: 'AbacatePay',
                  subtitle: 'Cobranca automatica via PIX',
                  value: abacatePayEnabled,
                  onChanged: onAbacatePayChanged,
                  icon: LucideIcons.zap,
                  iconColor: Colors.green,
                ),
                const SizedBox(height: 12),
                ModernSwitch(
                  title: 'Asaas',
                  subtitle: 'Pagamentos via PIX e cartao (subconta)',
                  value: false,
                  onChanged: null,
                  icon: LucideIcons.creditCard,
                  iconColor: Colors.grey,
                  disabled: true,
                ),
              ],
            ),
          ),

          // KYC Section — only when Asaas is enabled
          if (asaasEnabled) ...[
            const SizedBox(height: 16),
            _KycCard(
              kycStatus: kycStatus,
              kycOnboardingUrl: kycOnboardingUrl,
              isCheckingKyc: isCheckingKyc,
              onCheckKyc: onCheckKyc,
            ),
          ],
        ],
      ),
    );
  }
}

class _KycCard extends StatelessWidget {
  final String kycStatus;
  final String? kycOnboardingUrl;
  final bool isCheckingKyc;
  final VoidCallback onCheckKyc;

  const _KycCard({
    required this.kycStatus,
    required this.kycOnboardingUrl,
    required this.isCheckingKyc,
    required this.onCheckKyc,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
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
          _buildKycContent(context),
        ],
      ),
    );
  }

  Widget _buildKycContent(BuildContext context) {
    if (kycStatus == 'not_checked') {
      return ElevatedButton.icon(
        onPressed: isCheckingKyc ? null : onCheckKyc,
        icon: isCheckingKyc
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(LucideIcons.fileSearch, size: 18),
        label: Text(isCheckingKyc ? 'Verificando...' : 'Verificar Documentos'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.textPrimary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }

    if (kycStatus == 'approved') {
      return _buildInfoBox(
        color: AppTheme.success,
        icon: LucideIcons.checkCircle,
        title: 'Documentos Aprovados!',
        message: 'Sua conta esta totalmente verificada.',
      );
    }

    if (kycStatus == 'pending_review') {
      return Column(
        children: [
          _buildInfoBox(
            color: AppTheme.info,
            icon: LucideIcons.clock,
            title: 'Documentos em Analise',
            message:
                'Seus documentos estao sendo verificados. A aprovacao pode levar ate 48 horas.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: isCheckingKyc ? null : onCheckKyc,
            icon: isCheckingKyc
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.refreshCw, size: 16),
            label: Text(isCheckingKyc ? 'Atualizando...' : 'Atualizar Status'),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      );
    }

    // Rejected or pending upload
    final isRejected = kycStatus == 'rejected';

    return Column(
      children: [
        _buildInfoBox(
          color: isRejected ? AppTheme.error : AppTheme.warning,
          icon: LucideIcons.alertTriangle,
          title: isRejected ? 'Documentos Rejeitados' : 'Documentos Pendentes',
          message: isRejected
              ? 'Envie novamente os documentos solicitados.'
              : 'Complete a verificacao para ativar sua conta.',
        ),
        const SizedBox(height: 16),
        if (kycOnboardingUrl != null)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final uri = Uri.parse(kycOnboardingUrl!);
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
          _buildInfoBox(
            color: AppTheme.info,
            icon: LucideIcons.info,
            title: 'Link nao disponivel',
            message: 'Clique em "Atualizar Status" para tentar novamente.',
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: isCheckingKyc ? null : onCheckKyc,
          icon: isCheckingKyc
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.refreshCw, size: 16),
          label: Text(isCheckingKyc ? 'Atualizando...' : 'Atualizar Status'),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBox({
    required Color color,
    required IconData icon,
    required String title,
    required String message,
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
        ],
      ),
    );
  }
}
