import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/navigator_key.dart';
import '../../core/theme.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/portal_providers.dart';
import '../../providers/student_provider.dart';
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

    final academyName =
        ref.watch(academySettingsProvider).valueOrNull?.name ?? 'sua academia';

    // Resolve o conjunto de slides + ação final pelo papel efetivo.
    final _Tour tour;
    if (user.isAdmin) {
      tour = _adminTour(academyName);
    } else if (user.isInstructor) {
      tour = _professorTour(academyName);
    } else {
      // Aluno: se a conta NÃO está vinculada a uma ficha (currentStudent null),
      // desvia para o fluxo de vincular em vez do tour padrão (resolve o beco
      // sem saída de hoje).
      final student = ref.watch(currentStudentProvider).valueOrNull;
      tour = student == null
          ? _studentUnlinkedTour()
          : _studentTour(academyName);
    }

    Future<void> finish({bool navigateTo = false, bool persist = true}) async {
      // Esconde já (trava de sessão) — não depende da escrita dar certo.
      if (mounted) setState(() => _dismissed = true);
      // Navega via navigatorKey (o context do gate está ACIMA do router, então
      // context.go aqui estouraria "No GoRouter found in context").
      if (navigateTo && tour.finishRoute != null) {
        navigatorKey.currentContext?.go(tour.finishRoute!);
      }
      // Persiste "viu" cross-device só quando faz sentido. No tour do aluno
      // NÃO-vinculado, NÃO persistimos: o nudge "conecte sua conta" deve voltar
      // até a conta ser de fato vinculada (aí o gate troca pro tour de valor).
      if (!persist) return;
      try {
        await globalUserService.markOnboardingSeen(user.id);
        ref.invalidate(globalUserProvider);
      } catch (_) {
        // offline/erro: a trava de sessão já cobre; persiste na próxima vez.
      }
    }

    final hasRoute = tour.finishRoute != null;
    return OnboardingCarousel(
      slides: tour.slides,
      finishLabel: tour.finishLabel,
      // Não celebra (confete) quando o tour termina navegando p/ outro lugar.
      celebrate: !hasRoute,
      // Tour com rota (não-vinculado): concluir/pular navega e NÃO persiste.
      // Tour normal: persiste e fica no lugar.
      onDone: () => finish(navigateTo: hasRoute, persist: !hasRoute),
      onSkip: () => finish(navigateTo: hasRoute, persist: !hasRoute),
    );
  }
}

/// Conteúdo resolvido de um tour (slides + rótulo/rota do CTA final).
class _Tour {
  final List<OnboardingSlide> slides;
  final String finishLabel;
  final String? finishRoute;
  const _Tour(this.slides,
      {this.finishLabel = 'Começar', this.finishRoute});
}

// ---------------------------------------------------------------------------
// ALUNO (vinculado) — carrossel curto de VALOR: presença → evolução → tudo num
// lugar. Personalizado com o nome real da academia.
// ---------------------------------------------------------------------------
_Tour _studentTour(String academy) => _Tour([
      OnboardingSlide(
        icon: LucideIcons.userCheck,
        accent: AppTheme.success,
        eyebrow: 'PASSO 1 DE 3',
        title: 'Registre sua presença',
        body:
            'Faça check-in a cada treino e veja sua frequência e sequência '
            'crescerem. É o combustível da sua evolução.',
      ),
      OnboardingSlide(
        icon: LucideIcons.trendingUp,
        accent: AppTheme.getBeltColor('purple'),
        eyebrow: 'PASSO 2 DE 3',
        title: 'Evolua e rankeie',
        body:
            'Acompanhe seu progresso, suba de faixa/nível e dispute o ranking '
            'da $academy com a galera.',
      ),
      OnboardingSlide(
        icon: LucideIcons.sparkles,
        accent: AppTheme.info,
        eyebrow: 'PASSO 3 DE 3',
        title: 'Tudo num lugar só',
        body:
            'Avisos, eventos, competições, mensalidade e a sua jornada na '
            '$academy — tudo na palma da mão.',
      ),
    ], finishLabel: 'Começar');

// ALUNO (não vinculado) — resolve o beco sem saída: orienta a inserir o código.
_Tour _studentUnlinkedTour() => const _Tour([
      OnboardingSlide(
        icon: LucideIcons.link2,
        accent: AppTheme.info,
        eyebrow: 'QUASE LÁ',
        title: 'Conecte sua conta',
        body:
            'Sua conta ainda não está vinculada a um aluno. Use o código de '
            'convite que a sua academia te enviou para liberar tudo.',
      ),
    ], finishLabel: 'Inserir código', finishRoute: '/link-code');

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

// ---------------------------------------------------------------------------
// PROFESSOR / INSTRUTOR — mini welcome focado na ação central (chamada).
// ---------------------------------------------------------------------------
_Tour _professorTour(String academy) => _Tour([
      OnboardingSlide(
        icon: LucideIcons.clipboardCheck,
        accent: AppTheme.success,
        eyebrow: 'BEM-VINDO, PROFESSOR',
        title: 'Sua turma, simples',
        body:
            'Faça a chamada da turma em segundos e acompanhe a evolução de '
            'cada aluno da $academy.',
      ),
      OnboardingSlide(
        icon: LucideIcons.award,
        accent: AppTheme.getBeltColor('brown'),
        eyebrow: 'ACOMPANHE',
        title: 'Gradue e acompanhe',
        body:
            'Veja o progresso dos alunos e registre graduações conforme as '
            'permissões que o admin liberou para você.',
      ),
    ], finishLabel: 'Começar');
