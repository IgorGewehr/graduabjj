import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../providers/billing_provider.dart';

/// Banner de status da automação de cobrança — extraído de
/// `billing_reminders_screen.dart._buildAutomationBanner` (linhas ~322-371)
/// para ser reusado 1:1 pela tela Cobrança (sempre visível, ligada ou não) e
/// pelo Dashboard (SPEC_ONBOARDING_2026-07.md §1.4/Fatia 4 — só quando
/// desligada; some sozinho ao ativar).
///
/// DIVERGÊNCIA vs. a spec literal: o CTA "Ligar" agora abre o novo passo
/// `BillingActivationStep` (`/admin/comece-aqui/cobranca`, com preview real
/// da mensagem de WhatsApp) em vez do dialog de Configurações cru que o
/// código original chamava. É o próprio destino que esta wave de ativação
/// introduz para "ligar a automação" — manter o dialog antigo como alvo do
/// banner reusado seria inconsistente com o resto da spec (o dialog cru
/// continua acessível via o ícone de engrenagem no topo da tela Cobrança).
class BillingAutomationBanner extends ConsumerWidget {
  const BillingAutomationBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(billingAutomationStatusProvider).valueOrNull;
    // Enquanto carrega ou em erro, some — nunca pisca um estado errado.
    if (status == null) return const SizedBox.shrink();

    final on = status.whatsappEnabled;
    final color = on ? AppTheme.success : AppTheme.warning;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(
              on ? LucideIcons.checkCircle2 : LucideIcons.alertTriangle,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                on
                    ? 'Cobrança automática ligada — o sistema cobra sozinho pelo WhatsApp'
                    : 'Cobrança automática desligada',
                style: AppTheme.bodySmall.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!on)
              TextButton(
                onPressed: () => context.push('/admin/comece-aqui/cobranca'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('Ligar', style: TextStyle(fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }
}
