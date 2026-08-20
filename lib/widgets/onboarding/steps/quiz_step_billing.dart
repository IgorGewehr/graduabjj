import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../models/billing_payment_preference.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/portal_providers.dart';
import '../../../screens/admin/mercado_pago_connect_screen.dart';
import '../../../services/settings_service.dart';
import '../../form/input_field.dart';
import '../../polish/polish.dart';
import '../quiz_card_option.dart';

/// Passo 2 do Nível 1: Método de Cobrança & Chave PIX
class QuizStepBilling extends ConsumerStatefulWidget {
  final VoidCallback onNext;

  const QuizStepBilling({
    super.key,
    required this.onNext,
  });

  @override
  ConsumerState<QuizStepBilling> createState() => _QuizStepBillingState();
}

enum _BillingChoice { mercadoPago, pixManual, later }

class _QuizStepBillingState extends ConsumerState<QuizStepBilling> {
  _BillingChoice _choice = _BillingChoice.pixManual;
  final _pixKeyController = TextEditingController();
  PixKeyType _pixKeyType = PixKeyType.cpf;
  bool _mpConnected = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(academySettingsProvider).valueOrNull;
    if (settings != null) {
      _mpConnected = settings.mpConnected;
      if (settings.billingPaymentPreference == BillingPaymentPreference.mercadoPago) {
        _choice = _BillingChoice.mercadoPago;
      } else if (settings.hasPixKey) {
        _choice = _BillingChoice.pixManual;
        _pixKeyController.text = settings.pixKey ?? '';
        _pixKeyType = settings.pixKeyType ?? PixKeyType.cpf;
      }
    }
  }

  @override
  void dispose() {
    _pixKeyController.dispose();
    super.dispose();
  }

  Future<void> _connectMercadoPago() async {
    final academyId = ref.read(currentUserProvider).valueOrNull?.academyId;
    if (academyId == null) return;
    final connected = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MercadoPagoConnectScreen(
          academyId: academyId,
        ),
      ),
    );
    if (connected == true && mounted) {
      setState(() {
        _mpConnected = true;
        _choice = _BillingChoice.mercadoPago;
      });
      ref.invalidate(academySettingsProvider);
    }
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final academyId = ref.read(currentUserProvider).valueOrNull?.academyId;
      if (academyId != null) {
        final service = SettingsService(academyId);
        if (_choice == _BillingChoice.mercadoPago) {
          await service.updateBillingPaymentPreference(BillingPaymentPreference.mercadoPago);
        } else if (_choice == _BillingChoice.pixManual) {
          await service.updateBillingPaymentPreference(BillingPaymentPreference.manualPix);
          final key = _pixKeyController.text.trim();
          if (key.isNotEmpty) {
            await service.updatePixInfo(key, _pixKeyType);
          }
        }
        ref.invalidate(academySettingsProvider);
      }
      widget.onNext();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar financeiro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Como prefere receber as mensalidades?',
                style: AppTheme.headlineMedium.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Escolha a forma mais conveniente para sua academia cobrar os alunos.',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ).entrance(),
          const SizedBox(height: 20),
          QuizCardOption(
            title: 'PIX Direto na sua Conta',
            subtitle: 'Receba 100% do valor direto na sua conta bancária sem taxas.',
            badgeText: 'Mais Popular',
            badgeColor: AppTheme.success,
            icon: LucideIcons.qrCode,
            isSelected: _choice == _BillingChoice.pixManual,
            onTap: () => setState(() => _choice = _BillingChoice.pixManual),
          ),
          if (_choice == _BillingChoice.pixManual) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tipo de Chave PIX',
                    style: AppTheme.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: PixKeyType.values.map((type) {
                      final isSelected = _pixKeyType == type;
                      return ChoiceChip(
                        label: Text(type.label),
                        selected: isSelected,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : AppTheme.textPrimary,
                        ),
                        backgroundColor: Colors.white,
                        selectedColor: AppTheme.textPrimary,
                        onSelected: (_) => setState(() => _pixKeyType = type),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  InputField(
                    controller: _pixKeyController,
                    label: 'Sua Chave PIX',
                    hintText: _pixKeyType == PixKeyType.cpf
                        ? '000.000.000-00'
                        : _pixKeyType == PixKeyType.email
                            ? 'seu@email.com'
                            : _pixKeyType == PixKeyType.phone
                                ? '(00) 00000-0000'
                                : 'Chave PIX',
                    prefixIcon: LucideIcons.key,
                  ),
                ],
              ),
            ),
          ],
          QuizCardOption(
            title: 'Mercado Pago (Automático)',
            subtitle: 'Cobrança por cartão recorrente e PIX com baixa automática no sistema.',
            badgeText: 'Automatizado',
            badgeColor: AppTheme.info,
            icon: LucideIcons.creditCard,
            isSelected: _choice == _BillingChoice.mercadoPago,
            onTap: () => setState(() => _choice = _BillingChoice.mercadoPago),
          ),
          if (_choice == _BillingChoice.mercadoPago) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _mpConnected
                    ? AppTheme.success.withValues(alpha: 0.08)
                    : AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _mpConnected
                      ? AppTheme.success.withValues(alpha: 0.3)
                      : AppTheme.divider,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_mpConnected) ...[
                    Row(
                      children: [
                        const Icon(LucideIcons.checkCircle2, color: AppTheme.success, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Mercado Pago Conectado',
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sua conta está ativa para receber e dar baixa automática nas mensalidades.',
                      style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        const Icon(LucideIcons.info, color: AppTheme.info, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Conexão Necessária',
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Para emitir cobranças com baixa automática, conecte sua conta do Mercado Pago:',
                      style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _connectMercadoPago,
                        icon: const Icon(LucideIcons.link, size: 16),
                        label: const Text('Conectar Conta Mercado Pago'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF009EE3),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Você também pode continuar agora e conectar mais tarde em Configurações.',
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          QuizCardOption(
            title: 'Configurar financeiro mais tarde',
            subtitle: 'Pular este passo por enquanto e definir nas configurações depois.',
            icon: LucideIcons.clock,
            isSelected: _choice == _BillingChoice.later,
            onTap: () => setState(() => _choice = _BillingChoice.later),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Continuar',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
