import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/payment_providers.dart';
import '../../providers/portal_providers.dart';
import '../../providers/store_checkout_provider.dart';
import '../../providers/store_provider.dart';
import '../../services/abacate_pay_service.dart';
import '../../services/asaas_payment_service.dart';
import '../../services/firebase_service.dart';
import '../../services/mercado_pago_service.dart';
import '../../services/payment/payment_gateway_resolver.dart';
import '../../services/payment_service.dart' show PaymentMethodPolicy;
import '../../services/store_service.dart';
import '../../widgets/payment/payment_method_sheet.dart';
import '../../widgets/payment/payment_target.dart';
import '../../widgets/polish/polish.dart';

/// Multi-step store checkout (pickup-only): Review -> Payment.
///
/// Mirrors the marketplace `CheckoutScreen` look & feel (a [_CheckoutStepper]
/// header + an [AnimatedSwitcher] fade/slide between steps + a sticky
/// `_BottomActions` bar), adapted to [AppTheme] tokens. The state machine lives
/// in [storeCheckoutProvider]; this screen is the view.
///
/// Flow:
///  * Review  — cart items, total, an optional notes field and the "Retirada na
///    academia" pickup notice.
///  * Payment — the animated PIX/Cartao [PaymentMethodSheet] inline. The
///    "Confirmar R$ X" action calls [StoreCheckoutNotifier.placeOrder] (the
///    server validates prices/stock and derives the authoritative total), clears
///    the cart, fires the confetti and opens the payment sheet for the brand-new
///    pending order.
///
/// SECURITY: money stays server-authoritative — the client never sends the
/// amount; `StoreService.createOrder` re-prices from the database. The card
/// option is gated centrally inside [PaymentMethodSheet]
/// (`storeCreditCardEnabled && gateway.cardSupported`). [storeMinOrderAmount]
/// blocks confirmation with a friendly notice (never a dead-end charge).
class StoreCheckoutScreen extends ConsumerStatefulWidget {
  const StoreCheckoutScreen({super.key});

  @override
  ConsumerState<StoreCheckoutScreen> createState() =>
      _StoreCheckoutScreenState();
}

class _StoreCheckoutScreenState extends ConsumerState<StoreCheckoutScreen> {
  /// Gateway resolved once for this checkout (MP > Asaas > AbacatePay), reused
  /// by both the inline picker and the post-order payment sheet. Null while
  /// resolving; [PaymentGateway.none] when nothing is connected.
  PaymentGateway? _gateway;

  /// Local guard against a double-tap on "Confirmar" (the provider also guards
  /// via `isLoading`).
  bool _placing = false;

  @override
  void initState() {
    super.initState();
    _resolveGateway();
  }

  Future<void> _resolveGateway() async {
    try {
      final resolved = await ref
          .read(paymentGatewayProvider(FirebaseService.academyId).future);
      if (mounted) setState(() => _gateway = resolved);
    } catch (_) {
      // Falha transitória ao resolver: fica null e o Confirmar re-resolve
      // (com await) antes de decidir pular o sheet — nunca degrada para
      // 'sem gateway' silenciosamente.
    }
  }

  // --- Confirm -----------------------------------------------------------

  Future<void> _confirm() async {
    if (_placing) return;

    final items = ref.read(cartProvider);
    if (items.isEmpty) {
      context.showWarning('Seu carrinho esta vazio');
      return;
    }

    // Min-order gate (REAIS). Block with a friendly notice — never charge.
    final settings = await ref.read(academySettingsProvider.future);
    if (!mounted) return;
    final minOrder = settings?.storeMinOrderAmount;
    final total = ref.read(cartProvider.notifier).total;
    if (minOrder != null && minOrder > 0 && total < minOrder) {
      context.showWarning(
        'Pedido minimo de R\$ ${minOrder.toStringAsFixed(2)}. '
        'Adicione mais itens para continuar.',
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _placing = true);

    StoreOrder? order;
    try {
      // Server validates prices/stock and derives the authoritative total.
      order = await ref.read(storeCheckoutProvider.notifier).placeOrder();
    } finally {
      if (mounted) setState(() => _placing = false);
    }

    if (!mounted) return;

    if (order == null) {
      final error = ref.read(storeCheckoutProvider).error;
      context.showError(error ?? 'Nao foi possivel criar o pedido.');
      return;
    }

    // Order created (pending). Clear the cart — the order is now the source of
    // truth — and celebrate.
    ref.read(cartProvider.notifier).clear();
    HapticFeedback.heavyImpact();
    Celebration.confetti(context);
    context.showSuccess('Pedido criado! Conclua o pagamento.');

    await _openPaymentSheet(order);
  }

  /// Opens the shared [PaymentMethodSheet] for the freshly created [order]. If
  /// no gateway is connected, the order still exists as pending and the student
  /// is told to arrange payment with the academy.
  Future<void> _openPaymentSheet(StoreOrder order) async {
    var gateway = _gateway;
    final currentUser = ref.read(currentUserProvider).valueOrNull;

    // Resolução do initState ainda não concluiu (ou falhou): AGUARDA aqui em
    // vez de pular o pagamento silenciosamente — o pedido já existe e o aluno
    // precisa ver as opções de PIX/cartão.
    if (gateway == null) {
      try {
        // Invalida antes: um erro de rede no initState fica cacheado no
        // FutureProvider; sem isso o retry releria o mesmo erro.
        ref.invalidate(paymentGatewayProvider(FirebaseService.academyId));
        gateway = await ref
            .read(paymentGatewayProvider(FirebaseService.academyId).future);
        // Atribuição direta (sem capturar `gateway` em closure) para manter a
        // promoção de não-nulo até o uso no PaymentMethodSheet.
        _gateway = gateway;
        if (mounted) setState(() {});
      } catch (_) {
        gateway = null;
      }
      if (!mounted) return;
    }

    if (gateway == null) {
      // Falha ao resolver mesmo após retry: o pedido segue pendente e pode
      // ser pago pela lista de pedidos.
      context.showWarning(
          'Não foi possível carregar o pagamento online. Conclua o pagamento '
          'em "Meus pedidos" ou combine com a academia.');
      _goToOrders();
      return;
    }

    // Promoção não atravessa closures para locais reatribuídos — fixa o valor
    // não-nulo num final para uso no builder do sheet.
    final resolvedGateway = gateway;

    // Resolução CONCLUÍDA sem gateway conectado: avisa antes de navegar (em
    // vez de despejar o aluno na lista sem explicação).
    if (!resolvedGateway.pixEnabled || currentUser == null) {
      if (resolvedGateway == PaymentGateway.none) {
        context.showWarning(
            'Pagamento online não configurado — combine o pagamento '
            'diretamente com a academia.');
      }
      _goToOrders();
      return;
    }

    final settings = await ref.read(academySettingsProvider.future);
    if (!mounted) {
      _goToOrders();
      return;
    }
    final storeCreditCardEnabled = settings?.storeCreditCardEnabled ?? false;
    final description = _orderDescription(order);

    // Gate the offered methods by the order's policy snapshot AND the academy
    // card flag. If nothing is payable (e.g. card_only while the academy has
    // card disabled), explain it instead of opening an unusable sheet.
    final availability = StoreCheckoutMethodAvailability.from(
      policy: order.paymentMethodPolicy,
      storeCreditCardEnabled: storeCreditCardEnabled,
    );
    if (!availability.hasPayableMethod) {
      context.showWarning(_blockedReason(order.paymentMethodPolicy));
      _goToOrders();
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaymentMethodSheet(
        target: PaymentTarget.order(
          orderId: order.id,
          amount: order.total,
          description: description,
          studentId: currentUser.studentId ?? '',
          studentName: currentUser.displayName,
          paymentMethodPolicy: order.paymentMethodPolicy,
        ),
        gateway: resolvedGateway,
        // Card is offered only when the order policy allows it AND the academy
        // enabled store card. PIX is gated inside the sheet by the same policy.
        storeCreditCardEnabled: availability.creditCard,
        createPix: (cpf) => _createOrderPix(order, cpf: cpf),
        onSettled: _onPaymentSettled,
      ),
    );

    // Whether the student paid now or chose to pay later, the order already
    // exists — land them on the orders list so they can track/pay it.
    _goToOrders();
  }

  /// Human reason shown when an order has no payable method (so the buyer is
  /// never dropped into a dead-end sheet). The order still exists as pending —
  /// payment can be arranged with the academy.
  String _blockedReason(PaymentMethodPolicy policy) {
    if (policy == PaymentMethodPolicy.cardOnly) {
      return 'Este pedido aceita apenas cartao, mas o pagamento com cartao '
          'nao esta habilitado. Combine o pagamento com a academia.';
    }
    return 'Nenhum metodo de pagamento disponivel para este pedido. '
        'Combine o pagamento com a academia.';
  }

  /// Short order label used by the payment sheets (matches `store_orders_screen`).
  String _orderDescription(StoreOrder order) =>
      'Pedido #${order.id.substring(order.id.length - 6).toUpperCase()}';

  /// Creates the store-order PIX link for the resolved gateway. Only Mercado
  /// Pago needs/forwards the payer CPF; Asaas/AbacatePay ignore it. Amount is in
  /// REAIS (the services convert + the server re-derives it as cross-check).
  Future<PaymentLink?> _createOrderPix(StoreOrder order, {String? cpf}) async {
    final academyId = FirebaseService.academyId;
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser == null) return null;
    final studentId = currentUser.studentId ?? '';
    final description = _orderDescription(order);

    switch (_gateway) {
      case PaymentGateway.mercadoPago:
        return MercadoPagoService(academyId).createStoreOrderPayment(
          amount: order.total,
          orderId: order.id,
          studentId: studentId,
          studentName: currentUser.displayName,
          description: description,
          cpf: cpf,
        );
      case PaymentGateway.asaas:
        return AsaasPaymentService(academyId).createStoreOrderPayment(
          amount: order.total,
          orderId: order.id,
          studentId: studentId,
          studentName: currentUser.displayName,
          description: description,
        );
      case PaymentGateway.abacatePay:
        return AbacatePayService(academyId).createStoreOrderPayment(
          amount: order.total,
          orderId: order.id,
          studentId: studentId,
          studentName: currentUser.displayName,
          description: description,
        );
      case PaymentGateway.none:
      case null:
        return null;
    }
  }

  void _onPaymentSettled() {
    final studentId =
        ref.read(currentUserProvider).valueOrNull?.studentId ?? '';
    if (studentId.isNotEmpty) {
      ref.invalidate(studentOrdersProvider(studentId));
    }
    ref.invalidate(ordersProvider);
  }

  void _goToOrders() {
    if (!mounted) return;
    context.go('/portal/loja/pedidos');
  }

  // --- Build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final checkout = ref.watch(storeCheckoutProvider);
    final cart = ref.watch(cartProvider);
    final total = ref.read(cartProvider.notifier).total;

    // If the cart drained (e.g. order placed) and we are still on review,
    // there is nothing left to check out.
    if (cart.isEmpty && checkout.step == StoreCheckoutStep.review) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: _appBar(checkout.step),
        body: PolishedEmptyState(
          icon: LucideIcons.shoppingCart,
          title: 'Carrinho vazio',
          subtitle: 'Adicione produtos para finalizar um pedido',
          actionLabel: 'Ver Produtos',
          onAction: () => context.go('/portal/loja'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _appBar(checkout.step),
      body: Column(
        children: [
          _CheckoutStepper(currentStep: checkout.step),
          const Divider(height: 1),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.04, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(checkout.step),
                child: _buildStepContent(checkout, cart),
              ),
            ),
          ),
          _BottomActions(
            step: checkout.step,
            total: total,
            isLoading: _placing || checkout.isLoading,
            onConfirm: _confirm,
            onNext: () {
              HapticFeedback.selectionClick();
              ref.read(storeCheckoutProvider.notifier).nextStep();
            },
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _appBar(StoreCheckoutStep step) {
    return AppBar(
      backgroundColor: AppTheme.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title: const Text('Finalizar Pedido'),
      leading: IconButton(
        icon: const Icon(LucideIcons.arrowLeft),
        onPressed: () {
          if (step == StoreCheckoutStep.payment) {
            ref.read(storeCheckoutProvider.notifier).previousStep();
          } else {
            context.pop();
          }
        },
      ),
    );
  }

  Widget _buildStepContent(StoreCheckoutState state, List<StoreOrderItem> cart) {
    switch (state.step) {
      case StoreCheckoutStep.review:
        return _ReviewStep(
          items: cart,
          notes: state.notes,
          onNotesChanged: (v) =>
              ref.read(storeCheckoutProvider.notifier).setNotes(v),
        );
      case StoreCheckoutStep.payment:
        return _PaymentStep(
          items: cart,
          total: ref.read(cartProvider.notifier).total,
          gateway: _gateway,
        );
      case StoreCheckoutStep.processing:
      case StoreCheckoutStep.done:
        return const _ProcessingStep();
    }
  }
}

// ===========================================================================
// Stepper header
// ===========================================================================

/// Compact two-dot stepper (Revisao -> Pagamento), animated as the step
/// advances. Pickup-only, so there is no address/delivery node.
class _CheckoutStepper extends StatelessWidget {
  final StoreCheckoutStep currentStep;

  const _CheckoutStepper({required this.currentStep});

  int get _index {
    switch (currentStep) {
      case StoreCheckoutStep.review:
        return 0;
      case StoreCheckoutStep.payment:
      case StoreCheckoutStep.processing:
      case StoreCheckoutStep.done:
        return 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Row(
        children: [
          _node('Revisao', 0),
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: _index >= 1 ? AppTheme.primary : AppTheme.divider,
            ),
          ),
          _node('Pagamento', 1),
        ],
      ),
    );
  }

  Widget _node(String label, int step) {
    final active = _index >= step;
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: active ? AppTheme.primary : AppTheme.surfaceVariant,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '${step + 1}',
            style: AppTheme.bodySmall.copyWith(
              color: active ? Colors.white : AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTheme.bodyMedium.copyWith(
            color: active ? AppTheme.textPrimary : AppTheme.textSecondary,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Review step
// ===========================================================================

class _ReviewStep extends StatelessWidget {
  final List<StoreOrderItem> items;
  final String? notes;
  final ValueChanged<String?> onNotesChanged;

  const _ReviewStep({
    required this.items,
    required this.notes,
    required this.onNotesChanged,
  });

  double get _total => items.fold(0.0, (sum, i) => sum + i.subtotal);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Itens do pedido',
          style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ...List.generate(items.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ReviewItemRow(item: items[index]).entrance(index: index),
          );
        }),
        const SizedBox(height: 8),

        // Total
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: AppTheme.titleMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'R\$ ${_total.toStringAsFixed(2)}',
                style: AppTheme.headlineSmall.copyWith(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Notes
        Text(
          'Observacoes (opcional)',
          style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: notes,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          onChanged: onNotesChanged,
          decoration: InputDecoration(
            hintText: 'Ex.: tamanho, cor, ponto de retirada...',
            filled: true,
            fillColor: AppTheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.divider),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Pickup notice
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.store, size: 20, color: AppTheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Retirada na academia. Combine a entrega com a recepcao apos a confirmacao.',
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _ReviewItemRow extends StatelessWidget {
  final StoreOrderItem item;

  const _ReviewItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final variant = [item.size, item.color].whereType<String>().join(' - ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${item.quantity}x',
              style: AppTheme.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (variant.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    variant,
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            item.formattedSubtotal,
            style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Payment step
// ===========================================================================

/// The payment step shows the order summary and the inline PIX/Cartao
/// [PaymentMethodSheet] surface. Confirming on the bottom bar places the order
/// and (re)opens the sheet against the created order.
class _PaymentStep extends StatelessWidget {
  final List<StoreOrderItem> items;
  final double total;
  final PaymentGateway? gateway;

  const _PaymentStep({
    required this.items,
    required this.total,
    required this.gateway,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Pagamento',
          style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Ao confirmar, o pedido e criado e voce escolhe como pagar.',
          style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 16),

        // Summary card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${items.fold<int>(0, (s, i) => s + i.quantity)} itens',
                    style: AppTheme.bodyMedium.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  Text(
                    'R\$ ${total.toStringAsFixed(2)}',
                    style: AppTheme.bodyMedium,
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total a pagar',
                    style: AppTheme.titleMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'R\$ ${total.toStringAsFixed(2)}',
                    style: AppTheme.headlineSmall.copyWith(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Gateway hint — when none is connected, the order can still be placed
        // (pending) but payment is arranged with the academy.
        if (gateway == PaymentGateway.none)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.info,
                    size: 20, color: AppTheme.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Combine o pagamento diretamente com a academia.',
                    style: AppTheme.bodyMedium.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Row(
            children: [
              const Icon(LucideIcons.shieldCheck,
                  size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PIX e cartao (quando habilitado) na proxima etapa.',
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 40),
      ],
    );
  }
}

// ===========================================================================
// Processing step
// ===========================================================================

/// Contextual "creating your order" state shown while the order is being placed
/// — a spinner with a reassuring label instead of a bare, context-free
/// indicator.
class _ProcessingStep extends StatelessWidget {
  const _ProcessingStep();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Criando seu pedido...',
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ).fadeInQuick(),
    );
  }
}

// ===========================================================================
// Bottom actions
// ===========================================================================

/// Sticky bottom bar. On review it advances to payment ("Continuar"); on
/// payment it confirms the order ("Confirmar R$ X").
class _BottomActions extends StatelessWidget {
  final StoreCheckoutStep step;
  final double total;
  final bool isLoading;
  final VoidCallback onConfirm;
  final VoidCallback onNext;

  const _BottomActions({
    required this.step,
    required this.total,
    required this.isLoading,
    required this.onConfirm,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final isPayment = step == StoreCheckoutStep.payment;
    final label = isPayment
        ? 'Confirmar R\$ ${total.toStringAsFixed(2)}'
        : 'Continuar';

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: PolishButton(
        label: label,
        icon: isPayment ? LucideIcons.wallet : LucideIcons.arrowRight,
        isLoading: isLoading,
        radius: 12,
        // The press haptic is already fired by the call sites (_confirm /
        // onNext), so suppress the duplicate tick here.
        haptic: false,
        onPressed: isPayment ? onConfirm : onNext,
      ),
    );
  }
}
