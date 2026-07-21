import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../providers/billing_provider.dart';
import '../../providers/portal_providers.dart';
import '../../services/analytics_service.dart';
import '../../services/services.dart';
import '../common/academy_page_header.dart';
import '../form/input_field.dart';
import '../polish/polish.dart';

/// Passo "Como vai funcionar a cobrança" — o AHA da ativação
/// (SPEC_ONBOARDING_2026-07.md §0.2/§1.2). Renderiza uma bolha de WhatsApp DE
/// VERDADE (não um template cru com placeholders) usando
/// `BillingNotificationService.applyMessageTemplate` com dados de exemplo —
/// funciona mesmo sem o Mercado Pago conectado, porque `injectPaymentInfo`
/// simplesmente remove o bloco `[[PIX]]...[[/PIX]]` quando não há PIX.
///
/// Hoje é acessado como tela cheia via `/admin/comece-aqui/cobranca` (rota
/// nova em app.dart, alcançada pelo passo `billing` do
/// `ActivationChecklist`). O mesmo widget está pronto para ser embutido como
/// um passo do wizard `/admin/comece-aqui` (Fatia 7, fora desta fatia) — daí
/// o parâmetro [source] para a instrumentação já aceitar 'wizard'.
class BillingActivationStep extends ConsumerStatefulWidget {
  /// Origem para `billing_automation_enabled{source}` (spec §5):
  /// 'checklist' | 'wizard' | 'settings'.
  final String source;

  /// Fatia 7 — quando não-nulo, este passo está EMBUTIDO num fluxo externo
  /// (o wizard `/admin/comece-aqui`) em vez de ser uma rota própria: em vez
  /// de `Navigator.pop`/`context.go('/admin')`, delega ao chamador avançar
  /// pro próximo passo. [activated] é true quando o dono ativou de verdade,
  /// false quando saiu por "Agora não, prefiro cobrar na mão". `null`
  /// preserva o comportamento de sempre (rota própria, pop/go).
  final void Function(bool activated)? onDone;

  const BillingActivationStep({
    super.key,
    this.source = 'checklist',
    this.onDone,
  });

  @override
  ConsumerState<BillingActivationStep> createState() =>
      _BillingActivationStepState();
}

class _BillingActivationStepState extends ConsumerState<BillingActivationStep> {
  // Pré-marcados ON — só nesta tela o default muda de OFF pra ON (spec
  // §1.2): é o próprio ato de "ativar" que o dono está decidindo ao abrir
  // este passo.
  bool _whatsappEnabled = true;
  bool _autoTuitionEnabled = true;
  bool _saving = false;
  bool _sendingTest = false;

  final _amountController = TextEditingController(text: '150,00');

  @override
  void initState() {
    super.initState();
    // 1x por entrada na tela — initState roda uma vez por criação do widget,
    // ao contrário de build() (que re-roda a cada setState/troca de switch).
    AnalyticsService.logChecklistBillingViewed();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double get _fallbackAmount {
    final normalized = _amountController.text
        .replaceAll('.', '')
        .replaceAll(',', '.');
    return double.tryParse(normalized) ?? 150.0;
  }

  void _goBack({bool activated = false}) {
    if (widget.onDone != null) {
      widget.onDone!(activated);
      return;
    }
    if (Navigator.canPop(context)) {
      Navigator.of(context).maybePop();
    } else {
      context.go('/admin');
    }
  }

  Future<void> _activate() async {
    setState(() => _saving = true);
    try {
      final academyId = FirebaseService.academyId;
      final service = BillingReminderService(academyId);
      // Lê o estado atual primeiro: `saveNotificationSettings` grava com
      // merge:true mas SEMPRE inclui `emailEnabled` no payload (default
      // `false` do construtor) — construir um `BillingNotificationSettings`
      // do zero aqui desligaria silenciosamente o canal de Email se o dono
      // já tivesse ligado antes em Configurações. Preserva o que já existe,
      // só troca o WhatsApp + o link de pagamento (mesmos dois setters de
      // billing_reminders_screen.dart:2563-2584, só que sem perder estado).
      final current = await service.getNotificationSettings();
      await Future.wait([
        service.saveNotificationSettings(BillingNotificationSettings(
          whatsappEnabled: _whatsappEnabled,
          emailEnabled: current.emailEnabled,
          includePaymentLink: true,
          messageTemplates: current.messageTemplates,
        )),
        service.setAutoTuitionEnabled(_autoTuitionEnabled),
      ]);
      ref.invalidate(billingAutomationStatusProvider);
      unawaited(AnalyticsService.logBillingAutomationEnabled(
        source: widget.source,
        whatsappEnabled: _whatsappEnabled,
        autoTuition: _autoTuitionEnabled,
      ));
      if (!mounted) return;
      FeedbackUtils.showSuccess(context, 'Cobrança automática ativada!');
      _goBack(activated: true);
    } catch (e) {
      if (mounted) {
        FeedbackUtils.showError(context, 'Erro ao ativar: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Fatia 6 — abre o fluxo de cobrança-teste no WhatsApp do próprio dono.
  /// Pede telefone inline só quando `Academy.phone` está vazio, persiste 1x.
  Future<void> _openTestFlow(AcademySettings? settings, double amount) async {
    final existingPhone = settings?.phone?.trim() ?? '';
    final phoneController = TextEditingController(text: existingPhone);
    final academyName = settings?.name.trim().isNotEmpty == true
        ? settings!.name
        : 'Academia';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(LucideIcons.messageCircle, color: AppTheme.success, size: 22),
              const SizedBox(width: 10),
              const Expanded(child: Text('Testar no WhatsApp')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enviamos a mensagem de exemplo acima para o WhatsApp abaixo — '
                'assim você vê exatamente o que o aluno vai receber.',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              PhoneInput(controller: phoneController, label: 'WhatsApp da academia'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Enviar teste'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final digits = phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) {
      FeedbackUtils.showError(context, 'Informe um telefone válido com DDD.');
      return;
    }

    final phone = phoneController.text.trim();
    if (phone != existingPhone) {
      try {
        await ref.read(settingsServiceProvider)?.saveAcademySettings({'phone': phone});
        ref.invalidate(academySettingsProvider);
      } catch (_) {
        // Não bloqueia o envio do teste por falha ao salvar o telefone.
      }
    }

    setState(() => _sendingTest = true);
    try {
      final service = BillingReminderService(FirebaseService.academyId);
      final result = await service.sendTestBillingWhatsApp(
        academyName: academyName,
        phone: phone,
        amount: amount,
      );
      unawaited(AnalyticsService.logBillingTestSent(hasPix: result.hasPix));
      if (!mounted) return;
      if (result.success) {
        FeedbackUtils.showSuccess(
          context,
          'Mensagem de teste enviada! Confira seu WhatsApp.',
        );
      } else {
        FeedbackUtils.showError(
          context,
          result.error ?? 'Não foi possível enviar agora.',
        );
      }
    } finally {
      if (mounted) setState(() => _sendingTest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(activePlansProvider);
    final settingsAsync = ref.watch(academySettingsProvider);
    final settings = settingsAsync.valueOrNull;
    final plans = plansAsync.valueOrNull ?? const <Plan>[];
    final hasPlan = plans.isNotEmpty;
    final amount = hasPlan ? plans.first.monthlyValue : _fallbackAmount;
    final academyName = settings?.name.trim().isNotEmpty == true
        ? settings!.name
        : 'Academia';
    final mpConnected = settings?.mpConnected ?? false;

    final notificationService = BillingNotificationService(
      academyId: FirebaseService.academyId,
      academyName: academyName,
    );
    final previewMessage = notificationService.applyMessageTemplate(
      BillingNotificationService.defaultWhatsAppTemplates['D+1']!,
      'Aluno (exemplo)',
      amount,
      DateTime.now(),
      1,
      pixCode: null,
      ticketUrl: null,
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          AcademyPageHeader(
            compact: true,
            title: 'Cobrança automática',
            leading: Navigator.canPop(context)
                ? IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(LucideIcons.arrowLeft, size: 20),
                    tooltip: 'Voltar',
                  )
                : null,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Como vai funcionar a cobrança',
                    style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Quando o aluno atrasar, o app manda essa mensagem sozinho '
                    'pelo WhatsApp.',
                    style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 20),

                  if (!hasPlan) ...[
                    Text('Quanto custa sua mensalidade?', style: AppTheme.labelMedium),
                    const SizedBox(height: 8),
                    CurrencyInput(
                      controller: _amountController,
                      label: null,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Bolha de WhatsApp — mensagem DE VERDADE, com dados de
                  // exemplo (spec §1.2).
                  _WhatsAppBubble(message: previewMessage),
                  if (!mpConnected) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Sem código PIX ainda. Conecte o Mercado Pago quando '
                      'quiser para incluir o pagamento automático.',
                      style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Pressable(
                    onTap: _sendingTest ? null : () => _openTestFlow(settings, amount),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_sendingTest)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Icon(LucideIcons.send, size: 14, color: AppTheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            'Testar essa mensagem no meu WhatsApp agora',
                            style: AppTheme.labelMedium.copyWith(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 8),

                  SwitchListTile(
                    title: const Text('Cobrar automaticamente pelo WhatsApp'),
                    subtitle: Text(
                      'Régua D+0, D+1, D+3, D+7, D+15 e D+30, todo dia às 9h.',
                      style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                    ),
                    secondary: Icon(
                      LucideIcons.messageCircle,
                      color: _whatsappEnabled ? AppTheme.success : AppTheme.textSecondary,
                    ),
                    value: _whatsappEnabled,
                    activeThumbColor: AppTheme.success,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setState(() => _whatsappEnabled = v),
                  ),
                  SwitchListTile(
                    title: const Text('Gerar a mensalidade sozinha todo mês'),
                    subtitle: Text(
                      'Na virada do mês, gera as cobranças dos planos ativos.',
                      style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                    ),
                    secondary: Icon(
                      LucideIcons.repeat,
                      color: _autoTuitionEnabled ? AppTheme.success : AppTheme.textSecondary,
                    ),
                    value: _autoTuitionEnabled,
                    activeThumbColor: AppTheme.success,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setState(() => _autoTuitionEnabled = v),
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _activate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.textPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Ativar cobrança automática',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton(
                      onPressed: _saving ? null : _goBack,
                      child: Text(
                        'Agora não, prefiro cobrar na mão',
                        style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bolha de chat estilo WhatsApp — fundo verde-claro, renderiza a mensagem
/// JÁ resolvida (nome/valor/data preenchidos, bloco PIX presente ou removido).
class _WhatsAppBubble extends StatelessWidget {
  final String message;

  const _WhatsAppBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFDCF8C6),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(14),
          ),
          border: Border.all(color: AppTheme.success.withValues(alpha: 0.25)),
        ),
        child: Text(
          message,
          style: AppTheme.bodyMedium.copyWith(color: const Color(0xFF1B2E12)),
        ),
      ),
    );
  }
}
