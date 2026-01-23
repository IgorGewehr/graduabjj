import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'core/constants.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/portal/portal_shell.dart';
import 'screens/portal/home_screen.dart';
import 'screens/portal/profile_screen.dart';
import 'screens/portal/attendance_screen.dart';
import 'screens/portal/competitions_screen.dart';
import 'screens/portal/schedule_screen.dart';
import 'screens/portal/timeline_screen.dart';
import 'screens/portal/financial_screen.dart';
import 'screens/portal/behavior_screen.dart';
import 'screens/splash_screen.dart';
// Admin screens
import 'screens/admin/admin_screens.dart';

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

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isLoggingIn = state.matchedLocation == '/login';
      final isRegistering = state.matchedLocation == '/register';
      final isSplash = state.matchedLocation == '/';

      // Show splash while loading auth state
      if (authState.isLoading) {
        return null;
      }

      // If not logged in, redirect to login
      if (!isLoggedIn) {
        if (isLoggingIn || isRegistering) {
          return null;
        }
        return '/login';
      }

      // If logged in and trying to access auth pages, redirect to portal
      if (isLoggedIn && (isLoggingIn || isRegistering || isSplash)) {
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
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),

      // Portal Routes (Student Portal)
      ShellRoute(
        builder: (context, state, child) => PortalShell(child: child),
        routes: [
          GoRoute(
            path: '/portal',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/portal/perfil',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: '/portal/presencas',
            builder: (context, state) => const AttendanceScreen(),
          ),
          GoRoute(
            path: '/portal/competicoes',
            builder: (context, state) => const CompetitionsScreen(),
          ),
          GoRoute(
            path: '/portal/horarios',
            builder: (context, state) => const ScheduleScreen(),
          ),
          GoRoute(
            path: '/portal/linha-do-tempo',
            builder: (context, state) => const TimelineScreen(),
          ),
          GoRoute(
            path: '/portal/financeiro',
            builder: (context, state) => const FinancialScreen(),
          ),
          GoRoute(
            path: '/portal/comportamento',
            builder: (context, state) => const BehaviorScreen(),
          ),
        ],
      ),

      // Admin Routes
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          GoRoute(
            path: '/admin',
            builder: (context, state) => const AdminDashboardScreen(),
          ),
          GoRoute(
            path: '/admin/alunos',
            builder: (context, state) => const StudentsListScreen(),
          ),
          GoRoute(
            path: '/admin/alunos/novo',
            builder: (context, state) => const AdminStudentFormScreen(),
          ),
          GoRoute(
            path: '/admin/alunos/:id',
            builder: (context, state) => AdminStudentDetailScreen(
              studentId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/admin/alunos/:id/editar',
            builder: (context, state) => AdminStudentFormScreen(
              studentId: state.pathParameters['id'],
            ),
          ),
          GoRoute(
            path: '/admin/chamada',
            builder: (context, state) => const AdminAttendanceScreen(),
          ),
          GoRoute(
            path: '/admin/turmas',
            builder: (context, state) => const AdminClassesScreen(),
          ),
          GoRoute(
            path: '/admin/campeonatos',
            builder: (context, state) => const AdminCompetitionsScreen(),
          ),
          GoRoute(
            path: '/admin/financeiro',
            builder: (context, state) => const AdminFinancialScreen(),
          ),
          GoRoute(
            path: '/admin/graduacao',
            builder: (context, state) => const AdminGraduationScreen(),
          ),
          GoRoute(
            path: '/admin/relatorios',
            builder: (context, state) => const AdminReportsScreen(),
          ),
          GoRoute(
            path: '/admin/configuracoes',
            builder: (context, state) => const AdminSettingsScreen(),
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
