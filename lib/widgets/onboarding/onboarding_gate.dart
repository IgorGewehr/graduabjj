import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/portal_providers.dart';
import '../../services/global_user_service.dart';
import 'onboarding_carousel.dart';
import 'onboarding_slide.dart';

/// Portão do onboarding de boas-vindas — montado UMA vez no Stack do builder do
/// MaterialApp (acima do GoRouter, sobrevive a rebuilds do router, igual ao
/// overlay de criação de conta). Dispara o carrossel certo POR PAPEL no 1º
/// acesso e some para sempre ao concluir/pular (persistido em
/// users/{uid}.onboardingSeenAt, cross-device).
///
/// Regras de exibição (todas precisam ser verdadeiras):
///  - bootstrap == ready (mesmos dados que o shell precisa já resolvidos),
///  - há usuário logado,
///  - NÃO está criando conta (o overlay de criação tem prioridade),
///  - onboardingSeenAt == null (nunca viu).
class OnboardingGate extends ConsumerStatefulWidget {
  const OnboardingGate({super.key});

  @override
  ConsumerState<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends ConsumerState<OnboardingGate> {
  // Trava de SESSÃO: ao concluir/pular, esconde IMEDIATAMENTE e nunca reaparece
  // nesta sessão, mesmo que a escrita do flag falhe (offline) — senão o tour
  // entraria em loop. A persistência Firestore cuida das próximas sessões.
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final bootstrap = ref.watch(appBootstrapProvider);
    if (bootstrap != AppBootstrapStatus.ready) return const SizedBox.shrink();

    if (ref.watch(isCreatingAccountProvider)) return const SizedBox.shrink();

    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null) return const SizedBox.shrink();

    final globalUser = ref.watch(globalUserProvider).valueOrNull;
    // Enquanto o doc global não resolveu, não pinta (evita flash + evita marcar
    // como visto sem ter visto). Só dispara quando sabemos que é null.
    if (globalUser == null || globalUser.onboardingSeenAt != null) {
      return const SizedBox.shrink();
    }

    // Onboarding SÓ para o ADMIN/dono da academia (decisão do dono). Aluno e
    // professor NUNCA veem as mensagens iniciais de boas-vindas.
    if (!user.isAdmin) return const SizedBox.shrink();

    final academyName =
        ref.watch(academySettingsProvider).valueOrNull?.name ?? 'sua academia';
    final _Tour tour = _adminTour(academyName);

    Future<void> finish() async {
      // Esconde já (trava de sessão) — não depende da escrita dar certo.
      if (mounted) setState(() => _dismissed = true);
      // Persiste "viu" cross-device (o admin vê o tour uma única vez).
      try {
        await globalUserService.markOnboardingSeen(user.id);
        ref.invalidate(globalUserProvider);
      } catch (_) {
        // offline/erro: a trava de sessão já cobre; persiste na próxima vez.
      }
    }

    return OnboardingCarousel(
      slides: tour.slides,
      finishLabel: tour.finishLabel,
      celebrate: true,
      onDone: finish,
      onSkip: finish,
    );
  }
}

/// Conteúdo resolvido de um tour (slides + rótulo do CTA final).
class _Tour {
  final List<OnboardingSlide> slides;
  final String finishLabel;
  const _Tour(this.slides, {this.finishLabel = 'Começar'});
}

// ---------------------------------------------------------------------------
// ADMIN (dono) — boas-vindas curtas; a ativação detalhada vive no checklist do
// dashboard (derivado do estado real).
// ---------------------------------------------------------------------------
_Tour _adminTour(String academy) => _Tour([
      OnboardingSlide(
        icon: LucideIcons.rocket,
        accent: AppTheme.primary,
        eyebrow: 'BEM-VINDO',
        title: 'Vamos ativar a $academy',
        body:
            'Em poucos minutos sua academia estará no ar. Siga o checklist '
            '"Comece por aqui" no painel — a gente te guia.',
      ),
      OnboardingSlide(
        icon: LucideIcons.users,
        accent: AppTheme.info,
        eyebrow: 'GESTÃO COMPLETA',
        title: 'Tudo num painel',
        body:
            'Alunos, turmas, chamada, graduação e relatórios — sem planilha, '
            'sem grupo de WhatsApp bagunçado.',
      ),
      OnboardingSlide(
        icon: LucideIcons.wallet,
        accent: AppTheme.success,
        eyebrow: 'RECEBA PELO APP',
        title: 'Mensalidade no automático',
        body:
            'Conecte o Mercado Pago e receba via PIX e cartão direto na sua '
            'conta — sem taxa da plataforma.',
      ),
    ], finishLabel: 'Configurar academia');
