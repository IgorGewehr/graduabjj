import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../providers/providers.dart';
import '../../../services/services.dart';
import 'payment_card.dart';

class FinancialHeroCard extends ConsumerWidget {
  final VoidCallback? onPayPix;
  final VoidCallback? onCopyPix;

  const FinancialHeroCard({
    super.key,
    this.onPayPix,
    this.onCopyPix,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);
    final pixInfoAsync = ref.watch(pixInfoProvider);

    return studentAsync.when(
      data: (student) {
        if (student == null) return const SizedBox.shrink();

        final paymentsAsync =
            ref.watch(studentPaymentsProvider(student.id));

        return paymentsAsync.when(
          data: (payments) {
            final openPayments = payments
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

            final totalOpen = openPayments.fold<double>(
              0,
              (sum, p) => sum + p.value,
            );
            final overdueCount = openPayments
                .where((p) => p.status == PaymentStatus.overdue)
                .length;
            final pixKey =
                pixInfoAsync.valueOrNull?['key'] ?? '';

            return _HeroCardContent(
              openPayments: openPayments,
              totalOpen: totalOpen,
              overdueCount: overdueCount,
              pixKey: pixKey,
              onPayPix: onPayPix,
              onCopyPix: onCopyPix,
            );
          },
          loading: () => const _HeroCardSkeleton(),
          error: (_, e) => const SizedBox.shrink(),
        );
      },
      loading: () => const _HeroCardSkeleton(),
      error: (_, e) => const SizedBox.shrink(),
    );
  }
}

class _HeroCardContent extends StatefulWidget {
  final List<Payment> openPayments;
  final double totalOpen;
  final int overdueCount;
  final String pixKey;
  final VoidCallback? onPayPix;
  final VoidCallback? onCopyPix;

  const _HeroCardContent({
    required this.openPayments,
    required this.totalOpen,
    required this.overdueCount,
    required this.pixKey,
    this.onPayPix,
    this.onCopyPix,
  });

  @override
  State<_HeroCardContent> createState() => _HeroCardContentState();
}

class _HeroCardContentState extends State<_HeroCardContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _slideY;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slideY = Tween<double>(begin: -0.1, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasOpen = widget.openPayments.isNotEmpty;
    final hasOverdue = widget.overdueCount > 0;

    final Color cardBg;
    final Color borderColor;
    final Color accentColor;
    final String statusLabel;
    final IconData statusIcon;

    if (!hasOpen) {
      cardBg = AppTheme.successLight;
      borderColor = AppTheme.success.withValues(alpha: 0.3);
      accentColor = AppTheme.success;
      statusLabel = 'Em dia';
      statusIcon = LucideIcons.checkCircle;
    } else if (hasOverdue) {
      cardBg = AppTheme.errorLight;
      borderColor = AppTheme.error.withValues(alpha: 0.3);
      accentColor = AppTheme.error;
      statusLabel = 'Atrasado';
      statusIcon = LucideIcons.alertTriangle;
    } else {
      cardBg = AppTheme.warningLight;
      borderColor = AppTheme.warning.withValues(alpha: 0.3);
      accentColor = AppTheme.warning;
      statusLabel = 'Pendente';
      statusIcon = LucideIcons.clock;
    }

    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slideY.drive(
          Tween<Offset>(begin: const Offset(0, -0.1), end: Offset.zero),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(statusIcon, size: 22, color: accentColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasOpen
                              ? formatCurrency(widget.totalOpen)
                              : 'Tudo pago',
                          style: AppTheme.displayMedium.copyWith(
                            color: accentColor,
                            fontSize: 26,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasOpen
                              ? '${widget.openPayments.length} pagamento(s) em aberto'
                              : 'Nenhum pagamento pendente',
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusLabel,
                      style: AppTheme.labelSmall.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (hasOpen && widget.pixKey.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      LucideIcons.qrCode,
                      size: 14,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'PIX: ${widget.pixKey}',
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: widget.pixKey));
                        widget.onCopyPix?.call();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.copy,
                              size: 14,
                              color: AppTheme.textPrimary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Copiar',
                              style: AppTheme.labelSmall.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCardSkeleton extends StatelessWidget {
  const _HeroCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}
