import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../providers/providers.dart';
import '../../services/services.dart';
import '../../widgets/skeletons/skeletons.dart';
import 'financial/financial_hero_card.dart';
import 'financial/financial_history_tab.dart';
import 'financial/financial_plan_tab.dart';
import 'financial/financial_receipts_tab.dart';
import 'financial/payment_card.dart';
import 'financial/pix_payment_bottom_sheet.dart';

/// Payment enabled provider — reads from academySettingsProvider (Tatami-backed).
final abacatePayEnabledProvider = Provider<bool>((ref) {
  final settings = ref.watch(academySettingsProvider).valueOrNull;
  return settings?.isPaymentEnabled ?? false;
});

class FinancialScreen extends ConsumerWidget {
  const FinancialScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Financeiro'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Historico'),
              Tab(text: 'Plano Atual'),
              Tab(text: 'Recibos'),
            ],
          ),
        ),
        body: studentAsync.when(
          data: (student) {
            if (student == null) return const _NoStudentState();
            return RefreshIndicator(
              color: Theme.of(context).colorScheme.primary,
              onRefresh: () async {
                HapticFeedback.mediumImpact();
                ref.invalidate(studentPaymentsProvider(student.id));
                ref.invalidate(pixInfoProvider);
                ref.invalidate(academySettingsProvider);
              },
              child: _FinancialBody(student: student),
            );
          },
          loading: () => const _LoadingState(),
          error: (_, e) => const _ErrorState(),
        ),
      ),
    );
  }
}

class _FinancialBody extends ConsumerWidget {
  final dynamic student;

  const _FinancialBody({required this.student});

  void _showPixDialog(
      BuildContext context, Payment payment, String studentName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PixPaymentBottomSheet(
        payment: payment,
        studentName: studentName,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final abacatePayEnabled = ref.watch(abacatePayEnabledProvider);
    final paymentsAsync = ref.watch(studentPaymentsProvider(student.id));

    final rawOpen = paymentsAsync.valueOrNull
        ?.where(
          (p) =>
              p.status == PaymentStatus.pending ||
              p.status == PaymentStatus.overdue,
        )
        .toList();
    if (rawOpen != null) {
      rawOpen.sort((a, b) {
        if (a.status == PaymentStatus.overdue &&
            b.status != PaymentStatus.overdue) {
          return -1;
        }
        if (b.status == PaymentStatus.overdue &&
            a.status != PaymentStatus.overdue) {
          return 1;
        }
        return a.dueDate.compareTo(b.dueDate);
      });
    }
    final openPayments = rawOpen ?? <Payment>[];

    return NestedScrollView(
      headerSliverBuilder: (context, _) => [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _AcademyIndicator(),
                FinancialHeroCard(
                  onCopyPix: () =>
                      context.showSuccess('Chave PIX copiada!'),
                ),
                const SizedBox(height: 20),
                if (openPayments.isNotEmpty) ...[
                  Row(
                    children: [
                      Text(
                        'Em Aberto',
                        style: AppTheme.titleMedium
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          openPayments.length.toString(),
                          style: AppTheme.labelSmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...openPayments.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: PaymentCard(
                        payment: p,
                        showPayButton: abacatePayEnabled,
                        onPayPix: () =>
                            _showPixDialog(context, p, student.fullName),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ],
      body: const TabBarView(
        children: [
          FinancialHistoryTab(),
          FinancialPlanTab(),
          FinancialReceiptsTab(),
        ],
      ),
    );
  }
}

class _AcademyIndicator extends ConsumerWidget {
  const _AcademyIndicator();

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

class _NoStudentState extends StatelessWidget {
  const _NoStudentState();

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

class _LoadingState extends StatelessWidget {
  const _LoadingState();

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

class _ErrorState extends StatelessWidget {
  const _ErrorState();

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
