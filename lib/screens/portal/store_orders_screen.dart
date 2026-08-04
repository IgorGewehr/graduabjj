import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../services/store_service.dart';
import '../../services/abacate_pay_service.dart';
import '../../services/asaas_payment_service.dart';
import '../../services/mercado_pago_service.dart';
import '../../services/firebase_service.dart';
import '../../services/payment/payment_gateway_resolver.dart';
import '../../services/payment_service.dart' show PaymentMethodPolicy;
import '../../providers/payment_providers.dart';
import '../../providers/portal_providers.dart';
import '../../providers/store_checkout_provider.dart'
    show StoreCheckoutMethodAvailability;
import '../../providers/store_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/payment/payment_method_sheet.dart';
import '../../widgets/payment/payment_target.dart';
import '../../widgets/polish/polish.dart';
import '../../widgets/store/order_status_timeline.dart';

/// Portal Store Orders Screen - the student's own orders.
///
/// Admin/instructor order management lives in `StoreOrdersAdminScreen`
/// (`/admin/loja/pedidos`); this screen is intentionally student-only.
class PortalStoreOrdersScreen extends ConsumerWidget {
  const PortalStoreOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final studentId = currentUser?.studentId;

    // Students must be linked to a student record to see their orders.
    if (studentId == null) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: PolishedEmptyState(
          icon: LucideIcons.userX,
          title: 'Conta nao vinculada',
          subtitle: 'Voce precisa estar vinculado a um aluno para ver pedidos.',
        ),
      );
    }

    final ordersAsync = ref.watch(studentOrdersProvider(studentId));

    const title = 'Meus Pedidos';
    const subtitle = 'Acompanhe seus pedidos';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        color: Theme.of(context).colorScheme.primary,
        onRefresh: () async {
          HapticFeedback.mediumImpact();
          ref.invalidate(studentOrdersProvider(studentId));
        },
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (Navigator.canPop(context)) {
                          context.pop();
                        } else {
                          context.go('/portal/loja');
                        }
                      },
                      icon: const Icon(LucideIcons.arrowLeft),
                      style: IconButton.styleFrom(
                        backgroundColor: AppTheme.surfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppTheme.headlineMedium),
                          Text(
                            subtitle,
                            style: AppTheme.bodyMedium.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Orders List
            ordersAsync.when(
              data: (orders) {
                if (orders.isEmpty) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _OrderCard(
                          order: orders[index],
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _showOrderDetails(context, orders[index]);
                          },
                        ),
                      ).entrance(index: index),
                      childCount: orders.length,
                    ),
                  ),
                );
              },
              loading: () => SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: PolishSkeleton.shimmer(
                        child: const _OrderCardSkeleton(),
                      ),
                    ),
                    childCount: 3,
                  ),
                ),
              ),
              error: (error, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: PolishedEmptyState(
                  icon: LucideIcons.alertCircle,
                  title: 'Erro ao carregar pedidos',
                  subtitle: 'Verifique sua conexao e tente novamente.',
                  accent: AppTheme.error,
                  actionLabel: 'Tentar novamente',
                  onAction: () {
                    HapticFeedback.lightImpact();
                    ref.invalidate(studentOrdersProvider(studentId));
                  },
                ),
              ),
            ),

            // Bottom padding
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
        ),
      ),
    );
  }

  void _showOrderDetails(BuildContext context, StoreOrder order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _OrderDetailsSheet(order: order),
    );
  }
}

/// Empty State Widget
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return PolishedEmptyState(
      icon: LucideIcons.shoppingBag,
      title: 'Nenhum pedido ainda',
      subtitle: 'Seus pedidos aparecerao aqui',
      actionLabel: 'Ir para Loja',
      onAction: () => context.go('/portal/loja'),
    );
  }
}

/// Order Card Widget
class _OrderCard extends StatelessWidget {
  final StoreOrder order;
  final VoidCallback onTap;

  const _OrderCard({required this.order, required this.onTap});

  Color _getStatusColor() {
    switch (order.status) {
      case StoreOrderStatus.pendingPayment:
        return Colors.orange;
      case StoreOrderStatus.paid:
        return Colors.blue;
      case StoreOrderStatus.preparing:
        return Colors.purple;
      case StoreOrderStatus.ready:
        return Colors.green;
      case StoreOrderStatus.delivered:
        return Colors.grey;
      case StoreOrderStatus.cancelled:
        return AppTheme.error;
    }
  }

  IconData _getStatusIcon() {
    switch (order.status) {
      case StoreOrderStatus.pendingPayment:
        return LucideIcons.clock;
      case StoreOrderStatus.paid:
        return LucideIcons.checkCircle;
      case StoreOrderStatus.preparing:
        return LucideIcons.package;
      case StoreOrderStatus.ready:
        return LucideIcons.packageCheck;
      case StoreOrderStatus.delivered:
        return LucideIcons.truck;
      case StoreOrderStatus.cancelled:
        return LucideIcons.xCircle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final statusColor = _getStatusColor();
    // Highlight orders awaiting payment so they stand out in the list.
    final isNew = order.status == StoreOrderStatus.pendingPayment;

    return Pressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                isNew ? statusColor.withValues(alpha: 0.5) : AppTheme.divider,
            width: isNew ? 1.5 : 1,
          ),
          boxShadow: isNew
              ? [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Status Icon
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_getStatusIcon(), size: 20, color: statusColor),
                  ),
                  const SizedBox(width: 12),
                  // Order Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '#${order.id.substring(order.id.length - 6).toUpperCase()}',
                              style: AppTheme.titleMedium.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                                child: Container(
                                  key: ValueKey(order.status),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    order.status.label,
                                    style: AppTheme.labelSmall.copyWith(
                                      color: statusColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateFormat.format(order.createdAt),
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Total
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        order.formattedTotal,
                        style: AppTheme.titleMedium.copyWith(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${order.itemCount} itens',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Items Preview
              const SizedBox(height: 12),
              Text(
                order.items
                    .map((i) => '${i.quantity}x ${i.productName}')
                    .join(', '),
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderCardSkeleton extends StatelessWidget {
  const _OrderCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 80,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    width: 60,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Order Details Bottom Sheet
class _OrderDetailsSheet extends ConsumerStatefulWidget {
  final StoreOrder order;

  const _OrderDetailsSheet({required this.order});

  @override
  ConsumerState<_OrderDetailsSheet> createState() => _OrderDetailsSheetState();
}

class _OrderDetailsSheetState extends ConsumerState<_OrderDetailsSheet> {
  /// Resolved payment gateway for this academy. Loaded lazily for the student
  /// view so we can gate the PIX/Card buttons (and only forward the CPF to
  /// Mercado Pago). `null` while loading, [PaymentGateway.none] when nothing is
  /// connected (we then tell the student to arrange payment with the academy).
  PaymentGateway? _gateway;

  /// True when the gateway RESOLUTION failed (transient error — distinct from
  /// [PaymentGateway.none]). Shows a retry notice instead of an endless
  /// spinner or a misleading 'arrange with the academy'.
  bool _gatewayError = false;

  @override
  void initState() {
    super.initState();
    // Only a pending order needs the gateway resolution (to offer payment).
    if (widget.order.status == StoreOrderStatus.pendingPayment) {
      _resolveGateway();
    }
  }

  Future<void> _resolveGateway() async {
    // Single source of truth (cached per academy): MP > Asaas > AbacatePay.
    try {
      final resolved = await ref
          .read(paymentGatewayProvider(FirebaseService.academyId).future);
      if (mounted) {
        setState(() {
          _gateway = resolved;
          _gatewayError = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _gatewayError = true);
    }
  }

  /// Retry after a failed resolution: the FutureProvider caches the error, so
  /// invalidate it before resolving again.
  void _retryResolveGateway() {
    setState(() => _gatewayError = false);
    ref.invalidate(paymentGatewayProvider(FirebaseService.academyId));
    _resolveGateway();
  }

  Color _getStatusColor() {
    switch (widget.order.status) {
      case StoreOrderStatus.pendingPayment:
        return Colors.orange;
      case StoreOrderStatus.paid:
        return Colors.blue;
      case StoreOrderStatus.preparing:
        return Colors.purple;
      case StoreOrderStatus.ready:
        return Colors.green;
      case StoreOrderStatus.delivered:
        return Colors.grey;
      case StoreOrderStatus.cancelled:
        return AppTheme.error;
    }
  }

  /// Short order description used as the payment label.
  String get _orderDescription =>
      'Pedido #${widget.order.id.substring(widget.order.id.length - 6).toUpperCase()}';

  /// Creates the store-order PIX link for the resolved gateway. Only Mercado
  /// Pago needs/forwards the payer CPF (digits-only); Asaas/AbacatePay ignore
  /// it. Amount is passed in REAIS (the gateway services convert internally).
  Future<PaymentLink?> _createOrderPix({String? cpf}) async {
    final academyId = FirebaseService.academyId;
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser == null) return null;
    final studentId = currentUser.studentId ?? '';

    switch (_gateway) {
      case PaymentGateway.mercadoPago:
        return MercadoPagoService(academyId).createStoreOrderPayment(
          amount: widget.order.total,
          orderId: widget.order.id,
          studentId: studentId,
          studentName: currentUser.displayName,
          description: _orderDescription,
          cpf: cpf,
        );
      case PaymentGateway.asaas:
        return AsaasPaymentService(academyId).createStoreOrderPayment(
          amount: widget.order.total,
          orderId: widget.order.id,
          studentId: studentId,
          studentName: currentUser.displayName,
          description: _orderDescription,
        );
      case PaymentGateway.abacatePay:
        return AbacatePayService(academyId).createStoreOrderPayment(
          amount: widget.order.total,
          orderId: widget.order.id,
          studentId: studentId,
          studentName: currentUser.displayName,
          description: _orderDescription,
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

  /// Opens the shared [PaymentMethodSheet] (animated PIX/Cartao picker) for this
  /// pending order. The store credit-card option is gated centrally inside the
  /// sheet via `storeCreditCardEnabled && gateway.cardSupported` — we just read
  /// the academy flag here and forward it. The sheet then opens the existing
  /// PIX/Card sheets; no charge logic is rebuilt.
  Future<void> _openPaymentSheet() async {
    final gateway = _gateway;
    if (gateway == null || !gateway.pixEnabled) return;
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser == null) return;

    // Store-card gate: only offer the card when the academy enabled it.
    final settings = await ref.read(academySettingsProvider.future);
    if (!mounted) return;
    final storeCreditCardEnabled = settings?.storeCreditCardEnabled ?? false;

    // Gate the offered methods by the order's policy snapshot AND the academy
    // card flag. If nothing is payable, explain instead of opening a dead-end
    // sheet — the order stays pending and can be settled with the academy.
    final availability = StoreCheckoutMethodAvailability.from(
      policy: widget.order.paymentMethodPolicy,
      storeCreditCardEnabled: storeCreditCardEnabled,
    );
    if (!availability.hasPayableMethod) {
      context.showWarning(
        widget.order.paymentMethodPolicy == PaymentMethodPolicy.cardOnly
            ? 'Este pedido aceita apenas cartao, mas o pagamento com cartao nao '
                'esta habilitado. Combine o pagamento com a academia.'
            : 'Nenhum metodo de pagamento disponivel para este pedido. '
                'Combine o pagamento com a academia.',
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaymentMethodSheet(
        target: PaymentTarget.order(
          orderId: widget.order.id,
          amount: widget.order.total,
          description: _orderDescription,
          studentId: currentUser.studentId ?? '',
          studentName: currentUser.displayName,
          paymentMethodPolicy: widget.order.paymentMethodPolicy,
        ),
        gateway: gateway,
        // Card offered only when the order policy allows it AND the academy
        // enabled store card.
        storeCreditCardEnabled: availability.creditCard,
        createPix: (cpf) => _createOrderPix(cpf: cpf),
        onSettled: _onPaymentSettled,
      ),
    );
  }

  /// Builds the student-facing payment options for a pending order, gated on
  /// the resolved gateway. While resolving -> spinner; no gateway connected ->
  /// a friendly "arrange directly with the academy" notice (never a dead-end
  /// charge attempt); otherwise the shared PIX + Card sheets.
  List<Widget> _buildPaymentSection() {
    final gateway = _gateway;

    // Falha transitória ao resolver (≠ 'nada conectado'): erro com retry, sem
    // sumir com a opção de pagar nem fingir que não há gateway.
    if (gateway == null && _gatewayError) {
      return [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.wifiOff,
                  size: 18, color: AppTheme.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Não foi possível carregar o pagamento online.',
                  style: AppTheme.bodySmall
                      .copyWith(color: AppTheme.textSecondary),
                ),
              ),
              TextButton(
                onPressed: _retryResolveGateway,
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      ];
    }

    if (gateway == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ];
    }

    if (gateway == PaymentGateway.none) {
      return [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(
                LucideIcons.info,
                size: 20,
                color: AppTheme.textSecondary,
              ),
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
        ),
      ];
    }

    return [
      // Single entry point: the shared PaymentMethodSheet handles the
      // PIX/Cartao choice (and the centralized store-card gate).
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () {
            HapticFeedback.selectionClick();
            _openPaymentSheet();
          },
          icon: const Icon(LucideIcons.wallet),
          label: const Text('Pagar pedido'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final statusColor = _getStatusColor();

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pedido #${order.id.substring(order.id.length - 6).toUpperCase()}',
                          style: AppTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(opacity: animation, child: child),
                          child: Container(
                            key: ValueKey(order.status),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              order.status.label,
                              style: AppTheme.labelMedium.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateFormat.format(order.createdAt),
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Content
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Timeline
                    OrderStatusTimeline(order: order),
                    const SizedBox(height: 24),
                    // Items
                    Text(
                      'Itens do Pedido',
                      style: AppTheme.titleSmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...order.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceVariant,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                LucideIcons.package,
                                size: 20,
                                color: AppTheme.textSecondary,
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
                                  ),
                                  if (item.size != null || item.color != null)
                                    Text(
                                      [
                                        item.size,
                                        item.color,
                                      ].whereType<String>().join(' - '),
                                      style: AppTheme.bodySmall.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  item.formattedSubtotal,
                                  style: AppTheme.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${item.quantity}x ${item.formattedPrice}',
                                  style: AppTheme.labelSmall.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 32),
                    // Total
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total',
                          style: AppTheme.titleMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          order.formattedTotal,
                          style: AppTheme.headlineSmall.copyWith(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    if (order.notes?.isNotEmpty == true) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Observacoes',
                        style: AppTheme.titleSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(order.notes!),
                    ],

                    // Payment options for pending orders.
                    if (order.status == StoreOrderStatus.pendingPayment) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Formas de Pagamento',
                        style: AppTheme.titleSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._buildPaymentSection(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
