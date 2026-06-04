import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../services/abacate_pay_service.dart' show PaymentLink;
import '../../services/payment/payment_gateway_resolver.dart';
import '../payment_sheets.dart';
import '../polish/polish.dart';
import 'payment_target.dart';

/// Animated PIX / Cartao method picker, inspired by the marketplace's
/// `_PaymentMethodCard`. It is purely an orchestrator: selecting a method opens
/// the existing [PixPaymentSheet]/[CardPaymentSheet] (in `payment_sheets.dart`)
/// — it never reimplements any charge logic.
///
/// Capability gating (single place, UI side):
/// * PIX is offered whenever the resolved [gateway] is connected
///   ([PaymentGatewayCapabilities.pixEnabled]).
/// * The Cartao card is offered only when
///   `(target.isOrder ? settings.storeCreditCardEnabled : true) &&
///   gateway.cardSupported`. The store flag is re-enforced server-side in
///   `createMpCardPayment` (defense in depth); tuition is never gated by it.
///
/// The PIX link is produced by [createPix] (gateway-specific, owned by the
/// caller exactly as the call sites already build it). [target.amount] is
/// passed through only as a display value / server cross-check.
class PaymentMethodSheet extends StatelessWidget {
  final PaymentTarget target;

  /// The connected gateway resolved by the caller (single source of truth via
  /// `paymentGatewayProvider`). Drives the PIX/Cartao availability.
  final PaymentGateway gateway;

  /// Whether the academy enabled card payments for the STORE. Only gates the
  /// Cartao option for orders; ignored for tuition. Defaults to false (safe).
  final bool storeCreditCardEnabled;

  /// Creates (or regenerates) the PIX link for the resolved gateway. The CPF is
  /// passed through only for Mercado Pago ([PaymentGatewayCapabilities.requireCpf]);
  /// the other gateways ignore it. Returns null/throws on failure (the PIX sheet
  /// renders the friendly error + retry around it).
  final Future<PaymentLink?> Function(String? cpf) createPix;

  /// Called once the PIX/card payment settles, so the caller can invalidate the
  /// relevant providers. Forwarded verbatim to the underlying sheets.
  final VoidCallback? onSettled;

  /// Overrides whether the PIX sheet must capture the payer CPF before
  /// generating the link. When null, it defaults to the gateway capability
  /// ([PaymentGatewayCapabilities.requireCpf]). Callers pass `false` for a
  /// one-tap checkout when a valid CPF is already saved (and supplied through
  /// [createPix]); the value is otherwise the gateway default.
  final bool? requireCpf;

  const PaymentMethodSheet({
    super.key,
    required this.target,
    required this.gateway,
    required this.createPix,
    this.storeCreditCardEnabled = false,
    this.onSettled,
    this.requireCpf,
  });

  /// Whether the card option should be shown: store orders require the academy
  /// flag, tuition never does; both require a gateway that can charge a card.
  bool get _cardEnabled =>
      (target.isOrder ? storeCreditCardEnabled : true) && gateway.cardSupported;

  void _openPix(BuildContext context) {
    Navigator.pop(context);
    // The caller may already hold a valid saved CPF (one-tap checkout) and pass
    // requireCpf:false; otherwise fall back to the gateway capability.
    final requireCpf = this.requireCpf ?? gateway.requireCpf;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PixPaymentSheet(
        amount: target.amount,
        orderId: target.orderId,
        financialId: target.financialId,
        description: target.description,
        // Mercado Pago: capture CPF first, then create the PIX with it.
        requireCpf: requireCpf,
        onGenerateWithCpf: requireCpf ? (cpf) => createPix(cpf) : null,
        // Every gateway can regenerate after expiry / failed generation.
        onRegenerate: (cpf) => createPix(cpf),
        onPaymentConfirmed: onSettled,
      ),
    );
  }

  void _openCard(BuildContext context) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CardPaymentSheet(
        amount: target.amount,
        description: target.description,
        orderId: target.orderId,
        financialId: target.financialId,
        studentId: target.studentId,
        studentName: target.studentName,
        onPaymentSuccess: onSettled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardEnabled = _cardEnabled;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Como deseja pagar?',
                          style: AppTheme.headlineSmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'R\$ ${target.amount.toStringAsFixed(2)} · ${target.description}',
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.surfaceVariant,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              _PaymentMethodCard(
                icon: LucideIcons.qrCode,
                title: 'PIX',
                subtitle: 'Aprovacao instantanea',
                onTap: () {
                  HapticFeedback.selectionClick();
                  _openPix(context);
                },
              ),

              if (cardEnabled) ...[
                const SizedBox(height: 12),
                _PaymentMethodCard(
                  icon: LucideIcons.creditCard,
                  title: 'Cartao de credito',
                  subtitle: 'Parcele em ate 6x',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _openCard(context);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A single, tappable + animated payment-method card. Mirrors the marketplace's
/// `_PaymentMethodCard` (AnimatedContainer driven by a pressed/selected state),
/// adapted to [AppTheme] tokens.
class _PaymentMethodCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PaymentMethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_PaymentMethodCard> createState() => _PaymentMethodCardState();
}

class _PaymentMethodCardState extends State<_PaymentMethodCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = _pressed;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: PolishMotion.fast,
        curve: PolishMotion.press,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: highlighted
              ? AppTheme.primary.withValues(alpha: 0.06)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlighted
                ? AppTheme.primary
                : AppTheme.divider,
            width: highlighted ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: PolishMotion.fast,
              curve: PolishMotion.press,
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: highlighted
                    ? AppTheme.primary.withValues(alpha: 0.12)
                    : AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                widget.icon,
                color: highlighted ? AppTheme.primary : AppTheme.textPrimary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: AppTheme.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
