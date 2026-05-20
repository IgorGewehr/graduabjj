import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../providers/providers.dart';
import '../../../services/services.dart';
import '../../../widgets/skeletons/skeletons.dart';
import 'payment_card.dart';

class FinancialHistoryTab extends ConsumerWidget {
  const FinancialHistoryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);

    return studentAsync.when(
      data: (student) {
        if (student == null) return const SizedBox.shrink();

        final paymentsAsync =
            ref.watch(studentPaymentsProvider(student.id));

        return paymentsAsync.when(
          data: (payments) {
            final history = payments
                .where(
                  (p) =>
                      p.status == PaymentStatus.paid ||
                      p.status == PaymentStatus.cancelled,
                )
                .toList()
              ..sort((a, b) => b.dueDate.compareTo(a.dueDate));

            if (history.isEmpty) {
              return const _EmptyHistory();
            }

            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: history.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (_, i) => PaymentCard(
                payment: history[i],
                showStatus: true,
              ),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: SkeletonList(
              itemCount: 5,
              scrollable: false,
              padding: EdgeInsets.zero,
              showAvatar: false,
              itemHeight: 80,
            ),
          ),
          error: (_, e) => const _HistoryError(),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(20),
        child: SkeletonList(
          itemCount: 5,
          scrollable: false,
          padding: EdgeInsets.zero,
          showAvatar: false,
          itemHeight: 80,
        ),
      ),
      error: (_, e) => const _HistoryError(),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.history,
              size: 40,
              color: AppTheme.textDisabled,
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum pagamento no historico',
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

class _HistoryError extends StatelessWidget {
  const _HistoryError();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Erro ao carregar historico.',
        style: AppTheme.bodyMedium.copyWith(color: AppTheme.error),
      ),
    );
  }
}
