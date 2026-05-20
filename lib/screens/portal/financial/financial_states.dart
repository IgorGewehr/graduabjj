import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../providers/selected_academy_provider.dart';
import '../../../widgets/skeletons/skeletons.dart';

class FinancialNoStudentState extends StatelessWidget {
  const FinancialNoStudentState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                LucideIcons.receipt,
                size: 40,
                color: AppTheme.textDisabled,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Pagamentos',
              style:
                  AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Vincule sua conta a um aluno para ver os pagamentos.',
              style: AppTheme.bodyMedium
                  .copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class FinancialLoadingState extends StatelessWidget {
  const FinancialLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        SkeletonStats(count: 2, height: 80),
        SizedBox(height: 24),
        SkeletonList(
          itemCount: 5,
          scrollable: false,
          padding: EdgeInsets.zero,
          showAvatar: false,
          itemHeight: 80,
        ),
      ],
    );
  }
}

class FinancialErrorState extends StatelessWidget {
  const FinancialErrorState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.errorLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                LucideIcons.alertCircle,
                size: 40,
                color: AppTheme.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Erro ao carregar dados',
              style:
                  AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Tente novamente mais tarde.',
              style: AppTheme.bodyMedium
                  .copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class FinancialAcademyIndicator extends ConsumerWidget {
  const FinancialAcademyIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMultiple = ref.watch(hasMultipleAcademiesProvider);
    final academyInfo = ref.watch(currentAcademyInfoProvider);

    if (!hasMultiple || academyInfo == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.receipt, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pagamentos de',
                  style: AppTheme.labelSmall
                      .copyWith(color: AppTheme.textSecondary),
                ),
                Text(
                  academyInfo.name,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => context.push('/portal/academias'),
            icon: const Icon(LucideIcons.arrowRightLeft, size: 14),
            label: const Text('Trocar'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              textStyle:
                  AppTheme.labelSmall.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
