import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../api/repositories.dart' as tatami_repos;
import '../../../api/dto/store_dto.dart' as api_store;
import '../../../core/feedback_utils.dart';
import '../../../core/theme.dart';
import '../../../providers/selected_academy_provider.dart';
import '../../../services/abacate_pay_service.dart';

/// PIX Payment Bottom Sheet with real-time payment listener
class OrderPixPaymentSheet extends ConsumerStatefulWidget {
  final PaymentLink paymentLink;
  final String orderId;
  final double amount;
  final String studentId;
  final void Function()? onPaymentConfirmed;

  const OrderPixPaymentSheet({
    super.key,
    required this.paymentLink,
    required this.orderId,
    required this.amount,
    required this.studentId,
    this.onPaymentConfirmed,
  });

  @override
  ConsumerState<OrderPixPaymentSheet> createState() =>
      _OrderPixPaymentSheetState();
}

class _OrderPixPaymentSheetState extends ConsumerState<OrderPixPaymentSheet> {
  bool _paymentConfirmed = false;
  // Firestore listener removido na Fase 1 — polling Tatami é o único caminho.
  Timer? _orderPollTimer;

  @override
  void initState() {
    super.initState();
    _setupOrderListener();
  }

  @override
  void dispose() {
    _orderPollTimer?.cancel();
    super.dispose();
  }

  /// Listen to order status changes via Tatami polling (2s interval).
  /// Listener Firestore real-time removido na Fase 1.
  void _setupOrderListener() {
    final academyId = ref.read(safeAcademyIdProvider) ?? '';
    _orderPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (timer) async {
        if (!mounted) {
          timer.cancel();
          return;
        }
        try {
          final repo = ref.read(tatami_repos.storeRepoProvider);
          final o = await repo.getOrder(academyId, widget.orderId);
          if (!mounted) return;
          if (o.status == api_store.ApiOrderStatus.paid &&
              !_paymentConfirmed) {
            setState(() => _paymentConfirmed = true);
            timer.cancel();
            _showPaymentConfirmedDialog();
            widget.onPaymentConfirmed?.call();
          }
        } catch (_) {
          // Erro transiente — segue o polling sem propagar pra UI.
        }
      },
    );
  }

  void _showPaymentConfirmedDialog() {
    final sheetContext = context;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: AppTheme.successLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.checkCircle,
                size: 48,
                color: AppTheme.success,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Pagamento Confirmado!',
              style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Seu pedido foi pago com sucesso.',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext); // Close dialog
                if (mounted) Navigator.pop(sheetContext); // Close bottom sheet
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Fechar'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    LucideIcons.qrCode,
                    color: AppTheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pagar com PIX',
                        style: AppTheme.titleLarge.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Pedido #${widget.orderId.substring(widget.orderId.length - 6).toUpperCase()}',
                        style: AppTheme.bodyMedium.copyWith(
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
            const SizedBox(height: 24),
            // Amount
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Valor: ',
                    style: AppTheme.bodyLarge.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  Text(
                    'R\$ ${widget.amount.toStringAsFixed(2)}',
                    style: AppTheme.headlineMedium.copyWith(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // QR Code
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: QrImageView(
                data: widget.paymentLink.pixCode,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Escaneie o QR Code com o app do seu banco',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Copy Code Button
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.paymentLink.pixCode.length > 30
                          ? '${widget.paymentLink.pixCode.substring(0, 30)}...'
                          : widget.paymentLink.pixCode,
                      style: AppTheme.bodySmall.copyWith(
                        fontFamily: 'monospace',
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: widget.paymentLink.pixCode),
                      );
                      context.showSuccess('Codigo PIX copiado!');
                    },
                    icon: const Icon(LucideIcons.copy, size: 16),
                    label: const Text('Copiar'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Instructions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        LucideIcons.info,
                        size: 20,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Instrucoes',
                        style: AppTheme.titleSmall.copyWith(
                          color: Colors.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildInstruction('1', 'Abra o app do seu banco'),
                  const SizedBox(height: 8),
                  _buildInstruction('2', 'Escolha pagar via PIX'),
                  const SizedBox(height: 8),
                  _buildInstruction('3', 'Escaneie o QR Code ou cole o codigo'),
                  const SizedBox(height: 8),
                  _buildInstruction('4', 'Confirme o pagamento'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Real-time payment status indicator
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _paymentConfirmed
                    ? AppTheme.successLight
                    : AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_paymentConfirmed)
                    const Icon(
                      LucideIcons.checkCircle,
                      size: 18,
                      color: AppTheme.success,
                    )
                  else
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppTheme.primary,
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Text(
                    _paymentConfirmed
                        ? 'Pagamento confirmado!'
                        : 'Aguardando pagamento...',
                    style: AppTheme.bodySmall.copyWith(
                      color: _paymentConfirmed
                          ? AppTheme.success
                          : AppTheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  Widget _buildInstruction(String number, String text) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: AppTheme.labelSmall.copyWith(
                color: Colors.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
          ),
        ),
      ],
    );
  }
}
