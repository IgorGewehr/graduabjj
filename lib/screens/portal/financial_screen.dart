import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../providers/providers.dart';
import '../../services/services.dart';
import 'financial/financial_hero_card.dart';
import 'financial/financial_history_tab.dart';
import 'financial/financial_plan_tab.dart';
import 'financial/financial_receipts_tab.dart';
import 'financial/financial_states.dart';
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
            if (student == null) return const FinancialNoStudentState();
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
          loading: () => const FinancialLoadingState(),
          error: (_, e) => const FinancialErrorState(),
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

  List<Payment> _sortedOpenPayments(List<Payment>? all) {
    if (all == null) return [];
    final open = all
        .where(
          (p) =>
              p.status == PaymentStatus.pending ||
              p.status == PaymentStatus.overdue,
        )
        .toList()
      ..sort((a, b) {
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
    return open;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final abacatePayEnabled = ref.watch(abacatePayEnabledProvider);
    final paymentsAsync = ref.watch(studentPaymentsProvider(student.id));
    final openPayments = _sortedOpenPayments(paymentsAsync.valueOrNull);

    return NestedScrollView(
      headerSliverBuilder: (context, _) => [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FinancialAcademyIndicator(),
                FinancialHeroCard(
                  onCopyPix: () =>
                      context.showSuccess('Chave PIX copiada!'),
                ),
                if (openPayments.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _OpenPaymentsHeader(count: openPayments.length),
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

class _OpenPaymentsHeader extends StatelessWidget {
  final int count;

  const _OpenPaymentsHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Em Aberto',
          style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            count.toString(),
            style: AppTheme.labelSmall.copyWith(
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
