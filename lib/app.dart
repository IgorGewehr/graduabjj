import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'core/theme.dart';
import 'core/constants.dart';
import 'providers/auth_provider.dart';
import 'services/push_notification_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/link_code_screen.dart';
import 'screens/auth/instructor_code_screen.dart';
import 'screens/auth/create_academy_screen.dart';
import 'screens/portal/portal_shell.dart';
import 'screens/portal/home_screen.dart';
import 'screens/portal/profile_screen.dart';
import 'screens/portal/attendance_screen.dart';
import 'screens/portal/competitions_screen.dart';
import 'screens/portal/competition_detail_screen.dart';
import 'screens/portal/schedule_screen.dart';
import 'screens/portal/qr_scan_screen.dart';
import 'screens/portal/timeline_screen.dart';
import 'screens/portal/financial_screen.dart';
import 'screens/portal/notifications_screen.dart';
import 'screens/portal/behavior_screen.dart';
import 'screens/portal/store_screen.dart';
import 'screens/portal/cart_screen.dart';
import 'screens/portal/store_orders_screen.dart';
// Academy management screens
import 'screens/portal/academies_screen.dart';
import 'screens/portal/add_academy_screen.dart';
// Monitor screens
import 'screens/portal/monitor_attendance_screen.dart';
import 'screens/portal/monitor_students_screen.dart';
import 'screens/portal/monitor_student_detail_screen.dart';
import 'screens/portal/monitor_student_form_screen.dart';
import 'providers/portal_providers.dart';
import 'screens/splash_screen.dart';
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

/// Global Navigator Key for push notifications deep linking
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Router Provider
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final currentUser = ref.watch(currentUserProvider);
  final isCreatingAccount = ref.watch(isCreatingAccountProvider);

  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/',
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isLoggingIn = state.matchedLocation == '/login';
      final isRegistering = state.matchedLocation == '/register';
      final isLinkCode = state.matchedLocation == '/link-code';
      final isCreatingAcademy = state.matchedLocation == '/criar-academia';
      final isSplash = state.matchedLocation == '/';

      print(
        '[ROUTER] matchedLocation: ${state.matchedLocation}, isLoggedIn: $isLoggedIn, authLoading: ${authState.isLoading}, userLoading: ${currentUser.isLoading}, isCreatingAccount: $isCreatingAccount',
      );

      // Don't redirect while account creation is in progress
      if (isCreatingAccount) {
        print('[ROUTER] Account creation in progress, skipping redirect');
        return null;
      }

      // Show splash while loading auth state
      if (authState.isLoading) {
        return isSplash ? null : '/';
      }

      // If not logged in, redirect to login
      if (!isLoggedIn) {
        if (isLoggingIn || isRegistering || isLinkCode || isCreatingAcademy) {
          return null;
        }
        return '/login';
      }

      // If logged in, wait for user data to load before redirecting
      if (currentUser.isLoading) {
        print('[ROUTER] Waiting for user data to load...');
        return isSplash ? null : '/';
      }

      final user = currentUser.valueOrNull;
      print(
        '[ROUTER] User loaded: ${user?.displayName}, role: ${user?.role}, isAdmin: ${user?.isAdmin}, isInstructor: ${user?.isInstructor}',
      );

      // Inform notification service of user role for correct routing
      if (user != null) {
        pushNotificationService.setUserRole(
          isAdmin: user.isAdmin || user.isInstructor,
        );
      }

      // If logged in and on auth pages, redirect based on role
      if (isLoggingIn ||
          isRegistering ||
          isLinkCode ||
          isCreatingAcademy ||
          isSplash) {
        if (user != null && (user.isAdmin || user.isInstructor)) {
          print('[ROUTER] Redirecting admin/instructor to /admin');
          return '/admin';
        }
        print('[ROUTER] Redirecting to /portal');
        return '/portal';
      }

      return null;
    },
    routes: [
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

      // Portal Routes (Student Portal)
      ShellRoute(
        builder: (context, state, child) => PortalShell(child: child),
        routes: [
          // Main tab routes - instant/crossfade transitions
          GoRoute(
            path: '/portal',
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
            path: '/portal/horarios',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const ScheduleScreen(),
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
        ],
      ),

      // QR scanner (outside shell for fullscreen camera)
      GoRoute(
        path: '/portal/scan',
        pageBuilder: (context, state) => _buildPageWithPushTransition(
          context: context,
          state: state,
          child: const QrScanScreen(),
        ),
      ),

      // Portal Notifications (outside shell for full-screen overlay)
      GoRoute(
        path: '/portal/notificacoes',
        pageBuilder: (context, state) => _buildPageWithPushTransition(
          context: context,
          state: state,
          child: const NotificationsScreen(),
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
            path: '/admin/graduacao',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const AdminGraduationScreen(),
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
              child: const AdminSettingsScreen(),
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
            path: '/admin/carteira',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const AdminWalletScreen(),
            ),
          ),
          // Sub-pages
          GoRoute(
            path: '/admin/carteira/2fa-setup',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const TotpSetupScreen(),
            ),
          ),
          GoRoute(
            path: '/admin/loja/pedidos',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const PortalStoreOrdersScreen(),
            ),
          ),
        ],
      ),

      // Admin Notifications (outside shell for full-screen overlay)
      GoRoute(
        path: '/admin/notificacoes',
        pageBuilder: (context, state) => _buildPageWithPushTransition(
          context: context,
          state: state,
          child: const NotificationsScreen(),
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

    if (!isStaff && !isMonitor) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/portal');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return child;
  }
}
