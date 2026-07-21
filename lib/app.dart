import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'core/theme.dart';
import 'core/constants.dart';
import 'core/navigator_key.dart';
import 'core/navigation/nav_catalog.dart';
import 'providers/auth_provider.dart';
import 'services/push_notification_service.dart';
import 'services/analytics_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/link_code_screen.dart';
import 'screens/auth/instructor_code_screen.dart';
import 'screens/auth/create_academy_screen.dart';
import 'screens/portal/portal_shell.dart';
import 'screens/portal/home_screen.dart';
import 'screens/fighter/lutador_hub_screen.dart';
import 'screens/fighter/cena_screen.dart';
import 'screens/fighter/academia_hub_screen.dart';
import 'screens/fighter/diario_screen.dart';
import 'screens/portal/event_detail_screen.dart';
import 'screens/portal/jornal_screen.dart';
import 'screens/portal/ranking_screen.dart';
import 'screens/portal/profile_screen.dart';
import 'screens/portal/attendance_screen.dart';
import 'screens/portal/competitions_screen.dart';
import 'screens/portal/competition_detail_screen.dart';
import 'screens/portal/schedule_screen.dart';
import 'screens/portal/qr_scan_screen.dart';
import 'screens/portal/musculacao_qr_scan_screen.dart';
import 'screens/admin/admin_social_screen.dart';
import 'screens/admin/join_requests_screen.dart';
import 'screens/admin/musculacao_admin_screen.dart';
import 'screens/portal/workouts_screen.dart';
import 'screens/admin/workout_plans_screen.dart';
import 'screens/admin/exercises_screen.dart';
import 'screens/portal/videos_screen.dart';
import 'screens/admin/training_videos_screen.dart';
import 'screens/admin/import_students_screen.dart';
import 'screens/portal/timeline_screen.dart';
import 'screens/portal/evolution_screen.dart';
import 'screens/portal/my_sports_screen.dart';
import 'screens/portal/student_graduation_screen.dart';
import 'screens/portal/class_booking_screen.dart';
import 'screens/admin/class_bookings_admin_screen.dart';
import 'screens/portal/striking_screen.dart';
import 'screens/admin/combos_screen.dart';
import 'screens/admin/mesocycles_screen.dart';
import 'screens/portal/financial_screen.dart';
import 'screens/portal/notifications_screen.dart';
import 'screens/portal/behavior_screen.dart';
import 'screens/portal/store_screen.dart';
import 'screens/portal/cart_screen.dart';
import 'screens/portal/store_checkout_screen.dart';
import 'screens/portal/store_orders_screen.dart';
import 'screens/admin/store_orders_admin_screen.dart';
import 'screens/admin/devices_screen.dart';
import 'screens/admin/subscriptions_screen.dart';
// Academy management screens
import 'screens/portal/academies_screen.dart';
import 'screens/portal/add_academy_screen.dart';
// Monitor screens
import 'screens/portal/monitor_attendance_screen.dart';
import 'screens/portal/monitor_students_screen.dart';
import 'screens/portal/monitor_student_detail_screen.dart';
import 'screens/portal/monitor_student_form_screen.dart';
import 'screens/portal/public_profile_screen.dart';
import 'screens/portal/notification_prefs_screen.dart';
import 'providers/portal_providers.dart';
import 'providers/onboarding_providers.dart';
import 'screens/splash_screen.dart';
import 'screens/paywall_screen.dart';
import 'screens/kiosk/kiosk_screen.dart';
import 'widgets/onboarding/onboarding_gate.dart';
import 'widgets/onboarding/billing_activation_step.dart';
import 'widgets/common/back_button_handler.dart';
// Admin screens
import 'screens/admin/admin_screens.dart';

/// Smooth fade for tab/main routes — 150ms ease-in-out.
///
/// Replaces the previous `_buildPageInstant` (Duration.zero) so root tab
/// switches no longer flash. The duration is short enough to feel snappy
/// inside a bottom-nav shell, but long enough to give visual continuity.
CustomTransitionPage<T> _buildPageWithFade<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 150),
    reverseTransitionDuration: const Duration(milliseconds: 150),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
        child: child,
      );
    },
  );
}

/// Quick crossfade for tab switching - subtle and fast (150ms)
CustomTransitionPage<T> _buildPageWithCrossfade<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 150),
    reverseTransitionDuration: const Duration(milliseconds: 150),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
        child: child,
      );
    },
  );
}

/// iOS-style push transition - slide from right with parallax (250ms)
CustomTransitionPage<T> _buildPageWithPushTransition<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Primary animation - incoming page slides from right
      final primaryCurve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      // Secondary animation - outgoing page slides left (parallax effect)
      final secondaryCurve = CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).animate(primaryCurve),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset.zero,
            end: const Offset(-0.3, 0.0),
          ).animate(secondaryCurve),
          child: child,
        ),
      );
    },
  );
}

/// Fade-only transition for auth screens
CustomTransitionPage<T> _buildPageWithFadeTransition<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

/// Main App Widget
class GraduaBJJApp extends ConsumerWidget {
  const GraduaBJJApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final isCreatingAccount = ref.watch(isCreatingAccountProvider);
    final studentName = ref.watch(creatingAccountStudentNameProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR'), Locale('en', 'US')],
      locale: const Locale('pt', 'BR'),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.noScaling),
          child: Stack(
            children: [
              child!,
              if (isCreatingAccount)
                _AccountCreationOverlay(studentName: studentName),
              // Onboarding de boas-vindas — dispara o carrossel certo por papel
              // no 1º acesso e some ao concluir (persistido por usuário). Acima
              // do router p/ sobreviver a rebuilds; abaixo do overlay de criação
              // de conta (que tem prioridade via isCreatingAccount).
              const OnboardingGate(),
            ],
          ),
        );
      },
    );
  }
}

/// Full-screen overlay shown during account creation.
/// Lives above the GoRouter widget tree, so it survives router rebuilds.
class _AccountCreationOverlay extends StatelessWidget {
  final String studentName;

  const _AccountCreationOverlay({required this.studentName});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.background,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated loading icon
                Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                                width: 100,
                                height: 100,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppTheme.primary.withValues(alpha: 0.3),
                                  ),
                                ),
                              )
                              .animate(onPlay: (c) => c.repeat())
                              .rotate(duration: 2000.ms),
                          const Icon(
                            LucideIcons.userPlus,
                            size: 48,
                            color: AppTheme.primary,
                          ),
                        ],
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 300.ms)
                    .scale(begin: const Offset(0.8, 0.8)),

                const SizedBox(height: 40),

                Text(
                  'Criando sua conta...',
                  style: AppTheme.displaySmall,
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 100.ms),

                const SizedBox(height: 16),

                if (studentName.isNotEmpty)
                  Text(
                    'Vinculando ao perfil de $studentName',
                    style: AppTheme.bodyLarge.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 200.ms),

                const SizedBox(height: 32),

                // Progress indicators
                _OverlayProgressStep(
                  icon: LucideIcons.check,
                  text: 'Validando informacoes',
                  isCompleted: true,
                ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.2),

                const SizedBox(height: 12),

                _OverlayProgressStep(
                  icon: LucideIcons.loader,
                  text: 'Criando conta de acesso',
                  isActive: true,
                ).animate().fadeIn(delay: 400.ms).slideX(begin: -0.2),

                const SizedBox(height: 12),

                _OverlayProgressStep(
                  icon: LucideIcons.link,
                  text: 'Vinculando ao perfil do aluno',
                ).animate().fadeIn(delay: 500.ms).slideX(begin: -0.2),

                const SizedBox(height: 40),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.info,
                        color: AppTheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Aguarde enquanto preparamos tudo para voce...',
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 600.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayProgressStep extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isCompleted;
  final bool isActive;

  const _OverlayProgressStep({
    required this.icon,
    required this.text,
    this.isCompleted = false,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isCompleted
                ? AppTheme.success.withValues(alpha: 0.1)
                : isActive
                ? AppTheme.primary.withValues(alpha: 0.1)
                : AppTheme.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: isCompleted
                  ? AppTheme.success
                  : isActive
                  ? AppTheme.primary
                  : AppTheme.divider,
              width: 2,
            ),
          ),
          child: isActive
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.primary,
                      ),
                    ),
                  ),
                )
              : Icon(
                  icon,
                  size: 16,
                  color: isCompleted
                      ? AppTheme.success
                      : isActive
                      ? AppTheme.primary
                      : AppTheme.textDisabled,
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: AppTheme.bodyMedium.copyWith(
              color: isCompleted || isActive
                  ? AppTheme.textPrimary
                  : AppTheme.textSecondary,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}

/// Tracks whether the current signed-in session has already "landed" on its
/// post-login destination (portal/admin). Once landed, a transient re-fetch of
/// the user/settings/student providers (e.g. the selected-academy id flipping
/// from null to the primary id on first boot) must NOT bounce the user back to
/// the splash — that round-trip is exactly the "home flashes then reloads"
/// glitch. Reset on logout so the next session re-gates from scratch.
bool _sessionLanded = false;

/// TAREFA 1 (jul/2026) — token FCM em toda abertura autenticada.
///
/// Diagnóstico em prod: o token só era salvo nos fluxos EXPLÍCITOS de
/// login/criação de conta (auth_provider.dart chama
/// `pushNotificationService.onUserLogin()` dentro de signInWithEmail/
/// createAccount/etc). Um app reaberto com sessão JÁ autenticada (restore/
/// silent-login do FirebaseAuth — o caso mais comum no dia a dia: o usuário
/// mata e reabre o app) nunca passava por nenhum desses métodos, e por isso
/// só ~19% dos usuários tinham fcmTokens salvos.
///
/// Guard "1x por sessão de processo": o `redirect` do GoRouter roda a CADA
/// navegação depois que a sessão "pousa" (`_sessionLanded=true`), não só
/// quando o refreshListenable dispara — sem este latch, cada troca de aba
/// geraria um novo write no Firestore. Reseta junto com `_sessionLanded`
/// quando o bootstrap volta a `unauthenticated` (logout), pra a PRÓXIMA
/// sessão sincronizar de novo.
bool _pushTokenSyncedThisSession = false;

/// Router Provider
final routerProvider = Provider<GoRouter>((ref) {
  // Watch the coarse bootstrap status (auth + user + academy settings + linked
  // student). This is the single source of truth for "is the session ready to
  // render its shell without a follow-up loading flicker".
  // BUG CRÍTICO (corrigido): antes este provider fazia `ref.watch` do bootstrap
  // e do currentUser → a CADA reload transitório (ex.: abrir o Perfil dispara um
  // re-fetch do student/user) o provider RECRIAVA o GoRouter inteiro, que volta
  // ao `initialLocation: '/'` → o aluno era jogado pro /portal (Lutador) no 1º
  // clique. Agora o router é criado UMA vez e um refreshListenable re-roda só o
  // redirect quando bootstrap/user/criação mudam (sem recriar/resetar).
  final refresh = ValueNotifier<int>(0);
  // BUG CRÍTICO #2 (crash no LOGOUT, corrigido): bumpar o notifier SINCRONAMENTE
  // dentro do callback de ref.listen roda o redirect do GoRouter re-entrante,
  // no MEIO do flush do ProviderScheduler — o redirect faz ref.read de providers
  // dirty e muta o _HashMap interno de dependências enquanto o Riverpod o itera
  // → ConcurrentModificationError na RAIZ da árvore (UncontrolledProviderScope)
  // → app irrecuperável. Fix: coalescer os 3 listeners num único bump ADIADO
  // para o event-loop (Future(), não microtask), depois do flush terminar.
  var refreshScheduled = false;
  var disposed = false;
  void scheduleRefresh() {
    if (refreshScheduled || disposed) return;
    refreshScheduled = true;
    Future(() {
      refreshScheduled = false;
      if (!disposed) refresh.value++;
    });
  }

  ref.listen(appBootstrapProvider, (_, _) => scheduleRefresh());
  ref.listen(currentUserProvider, (_, _) => scheduleRefresh());
  ref.listen(isCreatingAccountProvider, (_, _) => scheduleRefresh());
  // Fatia 7 (SPEC_ONBOARDING_2026-07.md §0.1): o gate do wizard depende de
  // providers (turmas/alunos/presença) que resolvem DEPOIS do bootstrap —
  // sem este listener, uma academia genuinamente vazia podia "perder a
  // janela" do redirect se esses dados ainda estivessem carregando no
  // instante exato do pouso (ver [wizardGateStatusProvider] e o uso de
  // `state.matchedLocation == '/admin'` abaixo).
  ref.listen(wizardGateStatusProvider, (_, _) => scheduleRefresh());
  ref.onDispose(() {
    disposed = true;
    refresh.dispose();
  });

  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/',
    debugLogDiagnostics: true,
    refreshListenable: refresh,
    // Analytics (jul/2026): screen_view automático a cada navegação — null
    // fora de Android/iOS (ver AnalyticsService._enabled), então isto é um
    // no-op no build desktop. Nenhuma rota daqui seta `name:`, então o
    // GoRouter usa o TEMPLATE do path como screen_name (ex. '/portal/profile/
    // :id'), que é agregável e não vaza o id dinâmico no valor do evento.
    observers: [
      if (AnalyticsService.observer != null) AnalyticsService.observer!,
    ],
    redirect: (context, state) {
      final bootstrap = ref.read(appBootstrapProvider);
      final currentUser = ref.read(currentUserProvider);
      final isCreatingAccount = ref.read(isCreatingAccountProvider);
      final isLoggingIn = state.matchedLocation == '/login';
      final isRegistering = state.matchedLocation == '/register';
      final isLinkCode = state.matchedLocation == '/link-code';
      final isCreatingAcademy = state.matchedLocation == '/criar-academia';
      final isSplash = state.matchedLocation == '/';
      final isAuthRoute =
          isLoggingIn || isRegistering || isLinkCode || isCreatingAcademy;

      print(
        '[ROUTER] matchedLocation: ${state.matchedLocation}, bootstrap: $bootstrap, isCreatingAccount: $isCreatingAccount, landed: $_sessionLanded',
      );

      // Don't redirect while account creation is in progress
      if (isCreatingAccount) {
        print('[ROUTER] Account creation in progress, skipping redirect');
        return null;
      }

      // Not logged in: reset the landing latch and route to the auth flow.
      if (bootstrap == AppBootstrapStatus.unauthenticated) {
        _sessionLanded = false;
        // TAREFA 1: rearma o guard do token pra próxima sessão poder
        // sincronizar de novo (ex.: logout de um usuário e login de outro
        // sem reiniciar o processo).
        _pushTokenSyncedThisSession = false;
        if (isAuthRoute) return null;
        return '/login';
      }

      // Logged in but the session context is still resolving for the FIRST
      // time. Keep a single, stable splash until everything is ready. Once the
      // user has already landed (latch set), a transient reload must keep them
      // where they are instead of bouncing back to the splash.
      if (bootstrap == AppBootstrapStatus.loading) {
        print('[ROUTER] Bootstrap loading...');
        if (_sessionLanded) return null;
        // Já numa rota pós-login (portal/admin)? FICA — não rebate pro splash
        // só porque o bootstrap re-resolveu transitoriamente. Sem isso, abrir o
        // Perfil (ou trocar de aba) podia bouncar /portal/perfil → / → /portal.
        final loc = state.matchedLocation;
        if (loc.startsWith('/portal') || loc.startsWith('/admin')) return null;
        return isSplash ? null : '/';
      }

      // bootstrap == ready
      final user = currentUser.valueOrNull;
      print(
        '[ROUTER] Ready: ${user?.displayName}, role: ${user?.role}, isAdmin: ${user?.isAdmin}, isInstructor: ${user?.isInstructor}',
      );

      // Inform notification service of user role for correct routing
      if (user != null) {
        pushNotificationService.setUserRole(
          isAdmin: user.isAdmin || user.isInstructor,
        );
      }

      // If ready and sitting on an auth/splash page, redirect based on role.
      if (isAuthRoute || isSplash) {
        // Um usuário logado pode pousar EXPLICITAMENTE em /link-code para
        // vincular a conta (ex.: aluno sem ficha vindo do onboarding). Não
        // rebater para o portal — senão o CTA "Inserir código" morre na chegada.
        if (isLinkCode && user != null) return null;
        if (user != null) {
          // Admins always go to AdminShell.
          if (user.isAdmin) {
            print('[ROUTER] Redirecting admin to /admin');
            return '/admin';
          }

          if (user.isInstructor) {
            // Determine whether this instructor has a student account (was
            // promoted from a student) and whether they have financial access.
            final hasStudentId = user.studentId != null;
            final hasFinancial = user.hasPermission('financial:view') ||
                user.hasPermission('financial:create');

            // Some management permissions only have UI inside AdminShell
            // (e.g. the Campeonatos / Graduação screens). A student-instructor
            // holding one of those must reach /admin — /portal has no
            // competition-creation or graduation-management surface.
            final hasAdminOnlyManagement =
                user.hasPermission('competitions:create') ||
                user.hasPermission('graduation:manage');

            // Instructor who was a student AND has no financial perm AND no
            // admin-only management perm → send to the monitor/chamada portal
            // experience.
            if (hasStudentId && !hasFinancial && !hasAdminOnlyManagement) {
              print('[ROUTER] Redirecting student-instructor (no financial) to /portal');
              return '/portal';
            }

            // All other instructors (pure professors, or those with financial) →
            // AdminShell where nav is gated by permissions.
            print('[ROUTER] Redirecting instructor to /admin');
            return '/admin';
          }
        }
        print('[ROUTER] Redirecting to /portal');
        return '/portal';
      }

      // Kiosk/catraca: rota fullscreen fora dos shells. Defesa em profundidade —
      // só admin abre o totem (o botão em Settings só aparece com a feature
      // ligada, mas a URL direta precisa barrar aluno/não-admin).
      if (state.matchedLocation == '/kiosk') {
        if (user == null) return '/login';
        if (!user.isAdmin) return '/portal';
      }

      // Fatia 7 (SPEC_ONBOARDING_2026-07.md §0.1): gate do wizard "Comece em
      // 3 minutos". Só dispara quando o admin está exatamente na raiz
      // `/admin` (dashboard) — nunca intercepta um deep link direto pra uma
      // sub-rota (ex.: `/admin/configuracoes`), então não existe "trap": o
      // dono sempre pode navegar livremente, o wizard só aparece na landing
      // natural pós-login. `wizardGateStatusProvider.loading` (dados ainda
      // resolvendo) deixa passar sem decidir — o listener acima re-roda o
      // redirect assim que resolver, enquanto o admin ainda estiver em
      // `/admin`.
      if (user != null &&
          user.isAdmin &&
          state.matchedLocation == '/admin' &&
          ref.read(wizardGateStatusProvider) == WizardGateStatus.show) {
        return '/admin/comece-aqui';
      }

      // Ready AND already sitting on a post-login route → we've landed. Latch
      // so any subsequent transient reload keeps the user here (no splash
      // bounce). Stay put.
      _sessionLanded = true;

      // TAREFA 1: dispara o MESMO caminho idempotente de registro de token
      // que o login explícito usa (auth_provider.dart), agora também para
      // sessão restaurada silenciosamente — é exatamente aqui que o app
      // "decide que a sessão está pronta". addPostFrameCallback porque
      // `redirect` roda DURANTE a fase de build/navegação do GoRouter —
      // side-effects de rede/plugin nativo não podem rodar no meio disso.
      // onUserLogin() é best-effort e faz no-op sozinho se o FCM não foi
      // inicializado nesta sessão (guard `_initialized` interno) — cobre o
      // kill-switch do iOS (Tarefa 2): se o FCM não ligou, não há token a
      // salvar. No iOS o init roda deferido (main.dart) e pode terminar
      // DEPOIS deste ponto — por isso main.dart também chama onUserLogin()
      // logo após o init lá, fechando essa corrida (dupla chamada é segura:
      // mesmo token, mesmo merge:true).
      if (!_pushTokenSyncedThisSession) {
        _pushTokenSyncedThisSession = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          pushNotificationService.onUserLogin();
          // Analytics (jul/2026): mesmo latch do token FCM — "sessão pousou"
          // é exatamente o momento de contar app_open_auth (1x por sessão de
          // processo, não a cada troca de aba) e fixar o contexto de usuário
          // (uid/academia/role) pro resto dos eventos desta sessão. `user`
          // pode ser null aqui (ex.: rota fora de /kiosk sem sessão resolvida)
          // — nesse caso só o token sync roda, sem contexto pra fixar.
          AnalyticsService.logAppOpenAuthenticated();
          if (user != null) {
            AnalyticsService.setUserContext(
              uid: user.id,
              academyId: user.academyId,
              // `.name` (enum nativo) em vez do getter `.value` de
              // UserRoleExtension — evitar importar models/user.dart aqui só
              // pela extension; os valores são idênticos ('admin',
              // 'instructor', 'student', 'guardian').
              role: user.role.name,
            );
          }
        });
      }

      return null;
    },
    routes: [
      // Sprint B3 — DECISÃO INTENCIONAL: as rotas de splash e auth abaixo
      // (/, /login, /register, /link-code, /codigo-equipe, /criar-academia)
      // NÃO são envolvidas por BackButtonHandler. São telas PRÉ-LOGIN, onde o
      // voltar físico fechando o app é o comportamento esperado pelo usuário.
      // A proteção double-tap/parent só vale para rotas pós-login.

      // Splash Screen
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),

      // Auth Routes
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _buildPageWithFadeTransition(
          context: context,
          state: state,
          child: const LoginScreen(),
        ),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (context, state) => _buildPageWithPushTransition(
          context: context,
          state: state,
          child: const RegisterScreen(),
        ),
      ),
      GoRoute(
        path: '/link-code',
        pageBuilder: (context, state) => _buildPageWithPushTransition(
          context: context,
          state: state,
          child: const LinkCodeScreen(),
        ),
      ),
      GoRoute(
        path: '/codigo-equipe',
        pageBuilder: (context, state) => _buildPageWithPushTransition(
          context: context,
          state: state,
          child: const InstructorCodeScreen(),
        ),
      ),
      GoRoute(
        path: '/criar-academia',
        pageBuilder: (context, state) => _buildPageWithPushTransition(
          context: context,
          state: state,
          child: const CreateAcademyScreen(),
        ),
      ),

      // Kiosk / Catraca — totem fullscreen, FORA dos shells (sem AppBar, sem
      // navegação e sem o gate de assinatura). Lê o stream de accessEvents da
      // academia e mostra ✅ Bem-vindo / ❌ Financeiro pendente.
      GoRoute(
        path: '/kiosk',
        pageBuilder: (context, state) => _buildPageWithFadeTransition(
          context: context,
          state: state,
          child: const KioskScreen(),
        ),
      ),

      // Portal Routes (Student Portal)
      ShellRoute(
        builder: (context, state, child) => PortalShell(child: child),
        routes: [
          // Main tab routes - instant/crossfade transitions
          // B2C fighter-first: /portal é o HUB DO LUTADOR (identidade portátil).
          GoRoute(
            path: '/portal',
            pageBuilder: (context, state) => _buildPageWithFade(
              context: context,
              state: state,
              child: const LutadorHubScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/cena',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const CenaScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/academia',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const AcademiaHubScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/diario',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const DiarioScreen(),
            ),
          ),
          // Home antiga (academy-mixed) — mantida acessível em /portal/home.
          GoRoute(
            path: '/portal/home',
            pageBuilder: (context, state) => _buildPageWithFade(
              context: context,
              state: state,
              child: const HomeScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/perfil',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const ProfileScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/presencas',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const AttendanceScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/competicoes',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const CompetitionsScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/competicoes/:id',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: CompetitionDetailScreen(
                competitionId: state.pathParameters['id']!,
              ),
            ),
          ),
          GoRoute(
            path: '/portal/eventos/:id',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: EventDetailScreen(
                eventId: state.pathParameters['id']!,
              ),
            ),
          ),
          GoRoute(
            path: '/portal/jornal',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const JornalScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/horarios',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const ScheduleScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/ranking',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const RankingScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/linha-do-tempo',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const TimelineScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/evolucao',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const EvolutionScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/graduacao',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const StudentGraduationScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/reservas',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const ClassBookingScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/trocacao',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const StrikingScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/minhas-modalidades',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const MySportsScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/financeiro',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const FinancialScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/comportamento',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const BehaviorScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/loja',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const PortalStoreScreen(),
            ),
          ),
          // Sub-pages - iOS-style push transitions
          GoRoute(
            path: '/portal/loja/carrinho',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const PortalCartScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/loja/checkout',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const StoreCheckoutScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/loja/pedidos',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const PortalStoreOrdersScreen(),
            ),
          ),
          // Academy management routes
          GoRoute(
            path: '/portal/academias',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const AcademiesScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/academias/adicionar',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const AddAcademyScreen(),
            ),
          ),
          // Notification preferences (opt-out granular — §4 plano repaginada)
          GoRoute(
            path: '/portal/preferencias-notificacoes',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const NotificationPrefsScreen(),
            ),
          ),
          // Workout plans (structured training)
          GoRoute(
            path: '/portal/treinos',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const WorkoutsScreen(),
            ),
          ),
          // Training videos
          GoRoute(
            path: '/portal/videos',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const VideosScreen(),
            ),
          ),
          // Monitor routes (guarded — only academy staff or listed monitors).
          GoRoute(
            path: '/portal/chamada',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const _MonitorGuard(child: MonitorAttendanceScreen()),
            ),
          ),
          GoRoute(
            path: '/portal/alunos',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const _MonitorGuard(child: MonitorStudentsScreen()),
            ),
          ),
          GoRoute(
            path: '/portal/alunos/novo',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const _MonitorGuard(child: MonitorStudentFormScreen()),
            ),
          ),
          GoRoute(
            path: '/portal/alunos/:id',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: _MonitorGuard(
                child: MonitorStudentDetailScreen(
                  studentId: state.pathParameters['id']!,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/portal/alunos/:id/editar',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: _MonitorGuard(
                child: MonitorStudentFormScreen(
                  studentId: state.pathParameters['id'],
                ),
              ),
            ),
          ),
          // Read-only public student profile (in-shell push: Android back
          // returns to the previous portal route — see A7).
          GoRoute(
            path: '/portal/profile/:studentId',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: PublicProfileScreen(
                studentId: state.pathParameters['studentId']!,
              ),
            ),
          ),
        ],
      ),

      // QR scanner (outside shell for fullscreen camera)
      GoRoute(
        path: '/portal/scan',
        pageBuilder: (context, state) => _buildPageWithPushTransition(
          context: context,
          state: state,
          // Fora do ShellRoute: protege o voltar físico para retornar a /portal
          // em vez de fechar o app (deep-link/sem histórico de navigator).
          child: const BackButtonHandler(
            currentLocation: '/portal/scan',
            isRootRoute: false,
            child: QrScanScreen(),
          ),
        ),
      ),

      // Musculação self check-in scanner (fixed QR mode, fullscreen camera)
      GoRoute(
        path: '/portal/musculacao-checkin',
        pageBuilder: (context, state) => _buildPageWithPushTransition(
          context: context,
          state: state,
          child: const MusculacaoQrScanScreen(),
        ),
      ),

      // Portal Notifications (outside shell for full-screen overlay)
      GoRoute(
        path: '/portal/notificacoes',
        pageBuilder: (context, state) => _buildPageWithPushTransition(
          context: context,
          state: state,
          // Fora do ShellRoute: voltar retorna a /portal, nunca fecha o app.
          child: const BackButtonHandler(
            currentLocation: '/portal/notificacoes',
            isRootRoute: false,
            child: NotificationsScreen(),
          ),
        ),
      ),

      // Admin Routes
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          // Main tab routes - instant/crossfade transitions
          GoRoute(
            path: '/admin',
            pageBuilder: (context, state) => _buildPageWithFade(
              context: context,
              state: state,
              child: const AdminDashboardScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/alunos',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const StudentsListScreen(),
            ),
          ),
          // Sub-pages - iOS-style push transitions
          GoRoute(
            path: '/admin/alunos/novo',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const AdminStudentFormScreen(),
            ),
          ),
          // Solicitações de entrada (self-onboarding) — declarado ANTES de
          // '/admin/alunos/:id' senão o :id capturaria 'solicitacoes'.
          GoRoute(
            path: '/admin/alunos/solicitacoes',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const AdminJoinRequestsScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/alunos/:id',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: AdminStudentDetailScreen(
                studentId: state.pathParameters['id']!,
              ),
            ),
          ),
          GoRoute(
            path: '/admin/alunos/:id/editar',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: AdminStudentFormScreen(
                studentId: state.pathParameters['id'],
              ),
            ),
          ),
          // Main tab routes
          GoRoute(
            path: '/admin/chamada',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const AdminAttendanceScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/chamada/qr',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const AdminQrSessionScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/musculacao',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const MusculacaoAdminScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/treinos',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const WorkoutPlansScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/exercicios',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const ExercisesScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/reservas',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const ClassBookingsAdminScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/combinacoes',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const CombosScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/periodizacao',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const MesocyclesScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/videos',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const TrainingVideosScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/importar-alunos',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const ImportStudentsScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/turmas',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const AdminClassesScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/campeonatos',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const AdminCompetitionsScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/financeiro',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const AdminFinancialScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/assinaturas',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const AdminSubscriptionsScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/catracas',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const AdminDevicesScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/graduacao',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const AdminGraduationScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/graduacao/curriculo',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const SyllabusScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/ranking',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const RankingScreen(forStaff: true),
            ),
          ),
          GoRoute(
            path: '/admin/social',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const AdminSocialScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/relatorios',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const AdminReportsScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/cobranca',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const AdminBillingRemindersScreen(),
            ),
          ),
          // Passo "Como vai funcionar a cobrança" (SPEC_ONBOARDING_2026-07.md
          // §1.2/Fatia 5) — alcançado hoje pelo passo `billing` do
          // ActivationChecklist e pelo banner de automação do Dashboard/
          // Cobrança; preparado para ser reusado por um futuro wizard.
          GoRoute(
            path: '/admin/comece-aqui/cobranca',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const BillingActivationStep(),
            ),
          ),
          GoRoute(
            path: '/admin/retencao',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const AdminRetentionScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/configuracoes',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: AdminSettingsScreen(
                focusFeature: FeatureIdX.fromId(
                  state.uri.queryParameters['feature'],
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/admin/loja',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const AdminStoreScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/jornal',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const AdminEventsScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/jornal/novo',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const AdminEventFormScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/jornal/:id/editar',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: AdminEventFormScreen(
                eventId: state.pathParameters['id'],
              ),
            ),
          ),
          // Sub-pages
          GoRoute(
            path: '/admin/loja/pedidos',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const StoreOrdersAdminScreen(),
            ),
          ),
        ],
      ),

      // Wizard "Comece em 3 minutos" (Fatia 7, SPEC_ONBOARDING_2026-07.md
      // §0.1/§1.1) — fora do ShellRoute de propósito: sem bottom nav/rail do
      // AdminShell distraindo, cada passo é uma tela cheia de verdade. Só é
      // alcançado pelo gate do redirect acima; `isRootRoute: true` porque não
      // há "voltar" significativo (chegada é sempre via redirect pós-login,
      // igual /paywall).
      GoRoute(
        path: '/admin/comece-aqui',
        pageBuilder: (context, state) => _buildPageWithFadeTransition(
          context: context,
          state: state,
          child: const BackButtonHandler(
            currentLocation: '/admin/comece-aqui',
            isRootRoute: true,
            child: AdminOnboardingWizardScreen(),
          ),
        ),
      ),

      // Admin Notifications (outside shell for full-screen overlay)
      GoRoute(
        path: '/admin/notificacoes',
        pageBuilder: (context, state) => _buildPageWithPushTransition(
          context: context,
          state: state,
          // Fora do ShellRoute: voltar retorna a /admin, nunca fecha o app.
          child: const BackButtonHandler(
            currentLocation: '/admin/notificacoes',
            isRootRoute: false,
            child: NotificationsScreen(),
          ),
        ),
      ),

      // Paywall (rota navegável; o gate do admin também a renderiza inline).
      // showClose=true pois aqui é acesso voluntário (banner/deep link), com
      // botão de fechar — diferente do gate, que não tem saída.
      GoRoute(
        path: '/paywall',
        pageBuilder: (context, state) => _buildPageWithPushTransition(
          context: context,
          state: state,
          // Gate logado sem "pai" significativo: um único voltar NÃO pode
          // fechar o app (regra dura do dono). Usa double-tap-to-exit.
          child: const BackButtonHandler(
            currentLocation: '/paywall',
            isRootRoute: true,
            child: PaywallScreen(showClose: true),
          ),
        ),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppTheme.error),
            const SizedBox(height: 16),
            Text('Pagina nao encontrada', style: AppTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              state.matchedLocation,
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/portal'),
              child: const Text('Voltar ao inicio'),
            ),
          ],
        ),
      ),
    ),
  );
});

/// Restricts monitor portal screens to academy staff or users whose
/// studentId (or any linked studentId) is in the academy's `monitorIds`.
/// Redirects offenders to `/portal` after providers settle.
class _MonitorGuard extends ConsumerWidget {
  const _MonitorGuard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final settingsAsync = ref.watch(academySettingsProvider);

    if (userAsync.isLoading || settingsAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final user = userAsync.valueOrNull;
    final settings = settingsAsync.valueOrNull;

    final isStaff = user?.isAdmin == true || user?.isInstructor == true;
    final allStudentIds = <String>[
      if (user?.studentId != null) user!.studentId!,
      ...(user?.linkedStudentIds ?? const []),
    ];
    final monitorIds = settings?.monitorIds ?? const <String>[];
    final isMonitor = allStudentIds.any(monitorIds.contains);
    // Also allow users with attendance:take permission (promoted student-instructors).
    final hasAttendancePerm = user?.hasPermission('attendance:take') == true;

    if (!isStaff && !isMonitor && !hasAttendancePerm) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/portal');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return child;
  }
}
