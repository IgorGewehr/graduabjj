import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme.dart';
import 'core/constants.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/link_code_screen.dart';
import 'screens/portal/portal_shell.dart';
import 'screens/portal/home_screen.dart';
import 'screens/portal/profile_screen.dart';
import 'screens/portal/attendance_screen.dart';
import 'screens/portal/competitions_screen.dart';
import 'screens/portal/schedule_screen.dart';
import 'screens/portal/timeline_screen.dart';
import 'screens/portal/financial_screen.dart';
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
import 'screens/splash_screen.dart';
// Admin screens
import 'screens/admin/admin_screens.dart';

/// No transition - for instant tab switching (bottom nav)
CustomTransitionPage<T> _buildPageInstant<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
  );
}

/// Quick crossfade for tab switching - subtle and fast
CustomTransitionPage<T> _buildPageWithCrossfade<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 150),
    reverseTransitionDuration: const Duration(milliseconds: 100),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        ),
        child: child,
      );
    },
  );
}

/// iOS-style push transition - slide from right with parallax
CustomTransitionPage<T> _buildPageWithPushTransition<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
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

/// Fade + slight scale for modal-like pages
CustomTransitionPage<T> _buildPageWithScaleFade<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return FadeTransition(
        opacity: curvedAnimation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1.0).animate(curvedAnimation),
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
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        ),
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
      supportedLocales: const [
        Locale('pt', 'BR'),
        Locale('en', 'US'),
      ],
      locale: const Locale('pt', 'BR'),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: child!,
        );
      },
    );
  }
}

/// Router Provider
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final currentUser = ref.watch(currentUserProvider);

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isLoggingIn = state.matchedLocation == '/login';
      final isRegistering = state.matchedLocation == '/register';
      final isLinkCode = state.matchedLocation == '/link-code';
      final isSplash = state.matchedLocation == '/';

      print('[ROUTER] matchedLocation: ${state.matchedLocation}, isLoggedIn: $isLoggedIn, authLoading: ${authState.isLoading}, userLoading: ${currentUser.isLoading}');

      // Show splash while loading auth state
      if (authState.isLoading) {
        return isSplash ? null : '/';
      }

      // If not logged in, redirect to login
      if (!isLoggedIn) {
        if (isLoggingIn || isRegistering || isLinkCode) {
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
      print('[ROUTER] User loaded: ${user?.displayName}, role: ${user?.role}, isAdmin: ${user?.isAdmin}, isInstructor: ${user?.isInstructor}');

      // If logged in and on auth pages, redirect based on role
      if (isLoggingIn || isRegistering || isLinkCode || isSplash) {
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
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),

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

      // Portal Routes (Student Portal)
      ShellRoute(
        builder: (context, state, child) => PortalShell(child: child),
        routes: [
          // Main tab routes - instant/crossfade transitions
          GoRoute(
            path: '/portal',
            pageBuilder: (context, state) => _buildPageInstant(
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
          // Monitor routes
          GoRoute(
            path: '/portal/chamada',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const MonitorAttendanceScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/alunos',
            pageBuilder: (context, state) => _buildPageWithCrossfade(
              context: context,
              state: state,
              child: const MonitorStudentsScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/alunos/novo',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const MonitorStudentFormScreen(),
            ),
          ),
          GoRoute(
            path: '/portal/alunos/:id',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: MonitorStudentDetailScreen(
                studentId: state.pathParameters['id']!,
              ),
            ),
          ),
          GoRoute(
            path: '/portal/alunos/:id/editar',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: MonitorStudentFormScreen(
                studentId: state.pathParameters['id'],
              ),
            ),
          ),
        ],
      ),

      // Admin Routes
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          // Main tab routes - instant/crossfade transitions
          GoRoute(
            path: '/admin',
            pageBuilder: (context, state) => _buildPageInstant(
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
            path: '/admin/loja/pedidos',
            pageBuilder: (context, state) => _buildPageWithPushTransition(
              context: context,
              state: state,
              child: const PortalStoreOrdersScreen(),
            ),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: AppTheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Pagina nao encontrada',
              style: AppTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              state.matchedLocation,
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
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
