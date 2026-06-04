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
import '../../providers/store_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/payment_sheets.dart';
import '../../widgets/polish/polish.dart';

/// Portal Store Orders Screen - Student's Orders or All Orders for Admin/Instructor
class PortalStoreOrdersScreen extends ConsumerWidget {
  const PortalStoreOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final studentId = currentUser?.studentId;
    final isAdminOrInstructor =
        currentUser?.isAdmin == true || currentUser?.isInstructor == true;

    // For students without studentId, show error
    // For admin/instructor, show all orders
    if (studentId == null && !isAdminOrInstructor) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  LucideIcons.alertCircle,
                  size: 48,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Voce precisa estar vinculado a um aluno',
                  style: AppTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Use all orders for admin/instructor, student orders for students
    final ordersAsync = isAdminOrInstructor
        ? ref.watch(ordersProvider)
        : ref.watch(studentOrdersProvider(studentId!));

    final title = isAdminOrInstructor ? 'Pedidos da Loja' : 'Meus Pedidos';
    final subtitle = isAdminOrInstructor
        ? 'Gerencie os pedidos recebidos'
        : 'Acompanhe seus pedidos';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        color: Theme.of(context).colorScheme.primary,
        onRefresh: () async {
          HapticFeedback.mediumImpact();
          if (isAdminOrInstructor) {
            ref.invalidate(ordersProvider);
          } else {
            ref.invalidate(studentOrdersProvider(studentId!));
          }
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
                            _showOrderDetails(
                              context,
                              orders[index],
                              isAdminView: isAdminOrInstructor,
                            );
                          },
                          showStudentName: isAdminOrInstructor,
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
                    (context, index) => const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: _OrderCardSkeleton(),
                    ),
                    childCount: 3,
                  ),
                ),
              ),
              error: (error, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        LucideIcons.alertCircle,
                        size: 48,
                        color: AppTheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Erro ao carregar pedidos',
                        style: AppTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          if (isAdminOrInstructor) {
                            ref.invalidate(ordersProvider);
                          } else {
                            ref.invalidate(studentOrdersProvider(studentId!));
                          }
                        },
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
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

  void _showOrderDetails(
    BuildContext context,
    StoreOrder order, {
    bool isAdminView = false,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _OrderDetailsSheet(order: order, isAdminView: isAdminView),
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
  final bool showStudentName;

  const _OrderCard({
    required this.order,
    required this.onTap,
    this.showStudentName = false,
  });

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
          color: isNew ? statusColor.withValues(alpha: 0.5) : AppTheme.divider,
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
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
                        if (showStudentName) ...[
                          const SizedBox(height: 2),
                          Text(
                            order.studentName,
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
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
  final bool isAdminView;

  const _OrderDetailsSheet({required this.order, this.isAdminView = false});

  @override
  ConsumerState<_OrderDetailsSheet> createState() => _OrderDetailsSheetState();
}

class _OrderDetailsSheetState extends ConsumerState<_OrderDetailsSheet> {
  bool _isUpdatingStatus = false;

  /// Resolved payment gateway for this academy. Loaded lazily for the student
  /// view so we can gate the PIX/Card buttons (and only forward the CPF to
  /// Mercado Pago). `null` while loading, `_Gateway.none` when nothing is
  /// connected (we then tell the student to arrange payment with the academy).
  _Gateway? _gateway;

  @override
  void initState() {
    super.initState();
    // Only the student view (pending order) needs the gateway resolution.
    if (!widget.isAdminView &&
        widget.order.status == StoreOrderStatus.pendingPayment) {
      _resolveGateway();
    }
  }

  Future<void> _resolveGateway() async {
    final academyId = FirebaseService.academyId;
    // Precedence: Mercado Pago (mpConnected) > Asaas > AbacatePay.
    _Gateway resolved;
    try {
      if (await MercadoPagoService(academyId).isEnabled()) {
        resolved = _Gateway.mercadoPago;
      } else if (await AsaasPaymentService(academyId).isEnabled()) {
        resolved = _Gateway.asaas;
      } else if (await AbacatePayService(academyId).isEnabled()) {
        resolved = _Gateway.abacatePay;
      } else {
        resolved = _Gateway.none;
      }
    } catch (_) {
      resolved = _Gateway.none;
    }
    if (mounted) setState(() => _gateway = resolved);
  }

  Future<void> _updateStatus(StoreOrderStatus newStatus) async {
    final academyId = FirebaseService.academyId;

    setState(() => _isUpdatingStatus = true);

    try {
      final storeService = StoreService(academyId);
      await storeService.updateOrderStatus(widget.order.id, newStatus);
      if (mounted) {
        Navigator.pop(context);
        context.showSuccess('Status atualizado!');
        ref.invalidate(ordersProvider);
      }
    } catch (e) {
      if (mounted) {
        context.showError('Erro ao atualizar status: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStatus = false);
      }
    }
  }

  Future<void> _cancelOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar Pedido'),
        content: const Text('Tem certeza que deseja cancelar este pedido?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Nao'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Sim, Cancelar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _updateStatus(StoreOrderStatus.cancelled);
    }
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
      case _Gateway.mercadoPago:
        return MercadoPagoService(academyId).createStoreOrderPayment(
          amount: widget.order.total,
          orderId: widget.order.id,
          studentId: studentId,
          studentName: currentUser.displayName,
          description: _orderDescription,
          cpf: cpf,
        );
      case _Gateway.asaas:
        return AsaasPaymentService(academyId).createStoreOrderPayment(
          amount: widget.order.total,
          orderId: widget.order.id,
          studentId: studentId,
          studentName: currentUser.displayName,
          description: _orderDescription,
        );
      case _Gateway.abacatePay:
        return AbacatePayService(academyId).createStoreOrderPayment(
          amount: widget.order.total,
          orderId: widget.order.id,
          studentId: studentId,
          studentName: currentUser.displayName,
          description: _orderDescription,
        );
      case _Gateway.none:
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

  void _openPixSheet() {
    final gateway = _gateway;
    if (gateway == null || gateway == _Gateway.none) return;
    final requireCpf = gateway == _Gateway.mercadoPago;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PixPaymentSheet(
        amount: widget.order.total,
        orderId: widget.order.id,
        description: _orderDescription,
        // Mercado Pago: capture CPF first, then create the PIX with it.
        requireCpf: requireCpf,
        onGenerateWithCpf:
            requireCpf ? (cpf) => _createOrderPix(cpf: cpf) : null,
        // Allow regeneration after expiry / failed generation for every gateway.
        onRegenerate: (cpf) => _createOrderPix(cpf: cpf),
        onPaymentConfirmed: _onPaymentSettled,
      ),
    );
  }

  void _openCardSheet() {
    final gateway = _gateway;
    if (gateway == null || gateway == _Gateway.none) return;
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CardPaymentSheet(
        amount: widget.order.total,
        description: _orderDescription,
        orderId: widget.order.id,
        studentId: currentUser.studentId ?? '',
        studentName: currentUser.displayName,
        onPaymentSuccess: _onPaymentSettled,
      ),
    );
  }

  /// Builds the student-facing payment options for a pending order, gated on
  /// the resolved gateway. While resolving -> spinner; no gateway connected ->
  /// a friendly "arrange directly with the academy" notice (never a dead-end
  /// charge attempt); otherwise the shared PIX + Card sheets.
  List<Widget> _buildPaymentSection() {
    final gateway = _gateway;

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

    if (gateway == _Gateway.none) {
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
      // PIX Button
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _openPixSheet,
          icon: const Icon(LucideIcons.qrCode),
          label: const Text('Pagar com PIX'),
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
      const SizedBox(height: 12),
      // Card Button
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _openCardSheet,
          icon: const Icon(LucideIcons.creditCard),
          label: const Text('Pagar com Cartao'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            foregroundColor: AppTheme.primary,
            side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildAdminActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    bool outlined = false,
  }) {
    if (outlined) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _isUpdatingStatus ? null : onPressed,
          icon: _isUpdatingStatus
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Icon(icon, color: color),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isUpdatingStatus ? null : onPressed,
        icon: _isUpdatingStatus
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
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
                    _StatusTimeline(order: order),
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

                    // ADMIN VIEW: Customer info and status actions
                    if (widget.isAdminView) ...[
                      const SizedBox(height: 24),
                      // Customer Info
                      Text(
                        'Cliente',
                        style: AppTheme.titleSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: const Icon(
                                LucideIcons.user,
                                color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    order.studentName,
                                    style: AppTheme.titleSmall.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (order.studentId.isNotEmpty)
                                    Text(
                                      'ID: ${order.studentId.substring(0, order.studentId.length.clamp(0, 8))}...',
                                      style: AppTheme.bodySmall.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Status Actions for Admin
                      if (order.status != StoreOrderStatus.delivered &&
                          order.status != StoreOrderStatus.cancelled) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Acoes',
                          style: AppTheme.titleSmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Next status button based on current status
                        if (order.status == StoreOrderStatus.pendingPayment)
                          _buildAdminActionButton(
                            label: 'Marcar como Pago',
                            icon: LucideIcons.checkCircle,
                            color: Colors.green,
                            onPressed: () =>
                                _updateStatus(StoreOrderStatus.paid),
                          ),
                        if (order.status == StoreOrderStatus.paid)
                          _buildAdminActionButton(
                            label: 'Iniciar Preparo',
                            icon: LucideIcons.package,
                            color: Colors.purple,
                            onPressed: () =>
                                _updateStatus(StoreOrderStatus.preparing),
                          ),
                        if (order.status == StoreOrderStatus.preparing)
                          _buildAdminActionButton(
                            label: 'Marcar como Pronto',
                            icon: LucideIcons.packageCheck,
                            color: Colors.green,
                            onPressed: () =>
                                _updateStatus(StoreOrderStatus.ready),
                          ),
                        if (order.status == StoreOrderStatus.ready)
                          _buildAdminActionButton(
                            label: 'Marcar como Entregue',
                            icon: LucideIcons.truck,
                            color: Colors.blue,
                            onPressed: () =>
                                _updateStatus(StoreOrderStatus.delivered),
                          ),

                        const SizedBox(height: 12),
                        // Cancel button
                        _buildAdminActionButton(
                          label: 'Cancelar Pedido',
                          icon: LucideIcons.xCircle,
                          color: AppTheme.error,
                          outlined: true,
                          onPressed: _cancelOrder,
                        ),
                      ],
                    ]
                    // STUDENT VIEW: Payment Buttons for pending orders
                    else if (order.status ==
                        StoreOrderStatus.pendingPayment) ...[
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

/// Status Timeline Widget
class _StatusTimeline extends StatelessWidget {
  final StoreOrder order;

  const _StatusTimeline({required this.order});

  @override
  Widget build(BuildContext context) {
    final steps = [
      _TimelineStep(
        label: 'Criado',
        status: StoreOrderStatus.pendingPayment,
        isCompleted: true,
        isActive: order.status == StoreOrderStatus.pendingPayment,
      ),
      _TimelineStep(
        label: 'Pago',
        status: StoreOrderStatus.paid,
        isCompleted: order.isPaid,
        isActive: order.status == StoreOrderStatus.paid,
      ),
      _TimelineStep(
        label: 'Preparando',
        status: StoreOrderStatus.preparing,
        isCompleted:
            order.status == StoreOrderStatus.preparing ||
            order.status == StoreOrderStatus.ready ||
            order.status == StoreOrderStatus.delivered,
        isActive: order.status == StoreOrderStatus.preparing,
      ),
      _TimelineStep(
        label: 'Pronto',
        status: StoreOrderStatus.ready,
        isCompleted:
            order.status == StoreOrderStatus.ready ||
            order.status == StoreOrderStatus.delivered,
        isActive: order.status == StoreOrderStatus.ready,
      ),
      _TimelineStep(
        label: 'Entregue',
        status: StoreOrderStatus.delivered,
        isCompleted: order.status == StoreOrderStatus.delivered,
        isActive: order.status == StoreOrderStatus.delivered,
      ),
    ];

    if (order.status == StoreOrderStatus.cancelled) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.errorLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.xCircle, color: AppTheme.error),
            const SizedBox(width: 12),
            Text(
              'Pedido cancelado',
              style: AppTheme.titleSmall.copyWith(color: AppTheme.error),
            ),
          ],
        ),
      );
    }

    return Row(
      children: steps.asMap().entries.map((entry) {
        final index = entry.key;
        final step = entry.value;
        final isLast = index == steps.length - 1;

        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: step.isCompleted || step.isActive
                            ? AppTheme.primary
                            : AppTheme.surfaceVariant,
                        shape: BoxShape.circle,
                      ),
                      child: step.isCompleted
                          ? const Icon(
                              LucideIcons.check,
                              size: 14,
                              color: Colors.white,
                            )
                          : step.isActive
                          ? Container(
                              margin: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      step.label,
                      style: AppTheme.labelSmall.copyWith(
                        color: step.isCompleted || step.isActive
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary,
                        fontWeight: step.isActive
                            ? FontWeight.w600
                            : FontWeight.w500,
                        fontSize: 9,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Container(
                  width: 16,
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 20),
                  color: step.isCompleted
                      ? AppTheme.primary
                      : AppTheme.surfaceVariant,
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _TimelineStep {
  final String label;
  final StoreOrderStatus status;
  final bool isCompleted;
  final bool isActive;

  _TimelineStep({
    required this.label,
    required this.status,
    required this.isCompleted,
    required this.isActive,
  });
}

/// Payment gateway resolved for the academy, in precedence order
/// (Mercado Pago > Asaas > AbacatePay). [_Gateway.none] means no gateway is
/// connected, so payment must be arranged directly with the academy.
enum _Gateway { mercadoPago, asaas, abacatePay, none }
