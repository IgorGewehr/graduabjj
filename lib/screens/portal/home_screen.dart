import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';
import '../../widgets/skeletons/skeletons.dart';
import 'home/dynamic_cards_section.dart';
import 'home/home_academy_indicator.dart';
import 'home/pedidos_card.dart';
import 'home/quick_actions_grid.dart';
import 'home/stats_carousel.dart';
import 'home/welcome_header.dart';

/// Home Screen - Portal do Aluno (New Layout)
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final PageController _statsPageController = PageController(
    viewportFraction: 0.85,
  );
  int _currentStatsPage = 0;

  @override
  void dispose() {
    _statsPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final student = ref.watch(currentStudentProvider);

    final studentId = student.valueOrNull?.id;

    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      onRefresh: () async {
        HapticFeedback.mediumImpact();
        ref.invalidate(currentUserProvider);
        ref.invalidate(currentStudentProvider);
        ref.invalidate(upcomingCompetitionsProvider);
        if (studentId != null) {
          ref.invalidate(studentAttendanceCountProvider(studentId));
          ref.invalidate(studentMedalCountProvider(studentId));
          ref.invalidate(studentStreakProvider(studentId));
          ref.invalidate(studentMonthlyAttendanceProvider(studentId));
          ref.invalidate(studentNextClassProvider(studentId));
        }
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome header with belt badge
            student.when(
              data: (s) {
                if (s == null) {
                  return WelcomeHeader(
                    userName: currentUser.valueOrNull?.displayName.trim().isNotEmpty == true
                        ? currentUser.valueOrNull!.displayName
                        : 'Aluno',
                  );
                }
                return WelcomeHeaderWithBelt(
                  userName: s.displayName,
                  belt: s.currentBelt,
                  stripes: s.currentStripes,
                );
              },
              loading: () => WelcomeHeader(
                userName: currentUser.valueOrNull?.displayName.trim().isNotEmpty == true
                        ? currentUser.valueOrNull!.displayName
                        : 'Aluno',
              ),
              error: (_, __) => WelcomeHeader(
                userName: currentUser.valueOrNull?.displayName.trim().isNotEmpty == true
                        ? currentUser.valueOrNull!.displayName
                        : 'Aluno',
              ),
            ),

            // Academy indicator for multi-academy users
            const HomeAcademyIndicator(),

            const SizedBox(height: 16),

            // Meus Pedidos — acesso rapido logo apos header
            const PedidosCard(),

            const SizedBox(height: 24),

            // Stats Carousel
            student.when(
              data: (s) {
                if (s == null) return const SizedBox.shrink();
                return StatsCarousel(
                  student: s,
                  pageController: _statsPageController,
                  currentPage: _currentStatsPage,
                  onPageChanged: (page) {
                    setState(() => _currentStatsPage = page);
                  },
                );
              },
              loading: () => const SkeletonStats(count: 2, height: 140),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 24),

            // Dynamic Cards Section
            student.when(
              data: (s) {
                if (s == null) return const SizedBox.shrink();
                return DynamicCardsSection(
                  studentId: s.id,
                  onTap: (path) => context.go(path),
                );
              },
              loading: () => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonCard(height: 96, showAvatar: true),
                  SizedBox(height: 12),
                  SkeletonStats(count: 2, height: 96),
                  SizedBox(height: 12),
                  SkeletonCard(height: 80, showAvatar: true),
                ],
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 24),

            // Quick Actions Grid — features fora do bottom nav
            const QuickActionsGrid(),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}
