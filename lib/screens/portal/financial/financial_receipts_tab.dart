import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../providers/providers.dart';
import '../../../services/services.dart';
import '../../../widgets/skeletons/skeletons.dart';
import 'payment_card.dart';

/// Recibos tab: shows paid payments that act as receipts.
class FinancialReceiptsTab extends ConsumerWidget {
  const FinancialReceiptsTab({super.key});

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
            final receipts = payments
                .where((p) => p.status == PaymentStatus.paid)
                .toList()
              ..sort((a, b) => b.dueDate.compareTo(a.dueDate));

            if (receipts.isEmpty) {
              return const _EmptyReceipts();
            }

            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: receipts.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (_, i) => PaymentCard(
                payment: receipts[i],
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
          error: (_, e) => Center(
            child: Text(
              'Erro ao carregar recibos.',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.error),
            ),
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
      error: (_, e) => const SizedBox.shrink(),
    );
  }
}

class _EmptyReceipts extends StatelessWidget {
  const _EmptyReceipts();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.receipt,
              size: 40,
              color: AppTheme.textDisabled,
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum recibo disponivel',
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
