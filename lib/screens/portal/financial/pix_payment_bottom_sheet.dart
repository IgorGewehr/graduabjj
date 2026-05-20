import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../api/dto/financial_dto.dart' as api_fin;
import '../../../api/repositories.dart' as tatami_repos;
import '../../../core/feedback_utils.dart';
import '../../../core/theme.dart';
import '../../../providers/providers.dart';
import '../../../services/services.dart';
import 'payment_card.dart';

class PixPaymentBottomSheet extends ConsumerStatefulWidget {
  final Payment payment;
  final String studentName;

  const PixPaymentBottomSheet({
    super.key,
    required this.payment,
    required this.studentName,
  });

  @override
  ConsumerState<PixPaymentBottomSheet> createState() =>
      _PixPaymentBottomSheetState();
}

class _PixPaymentBottomSheetState
    extends ConsumerState<PixPaymentBottomSheet> {
  bool _isLoading = true;
  PaymentLink? _paymentLink;
  String? _error;
  bool _paymentConfirmed = false;
  Timer? _paymentPollTimer;

  @override
  void initState() {
    super.initState();
    _generatePixPayment();
    _setupPaymentListener();
  }

  @override
  void dispose() {
    _paymentPollTimer?.cancel();
    super.dispose();
  }

  void _setupPaymentListener() {
    final academyId = ref.read(selectedAcademyIdProvider) ?? '';

    _paymentPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (timer) async {
        if (!mounted) {
          timer.cancel();
          return;
        }
        try {
          final repo = ref.read(tatami_repos.financialRepoProvider);
          final f = await repo.getById(academyId, widget.payment.id);
          if (!mounted) return;
          if (f.status == api_fin.ApiFinancialStatus.paid &&
              !_paymentConfirmed) {
            setState(() => _paymentConfirmed = true);
            timer.cancel();
            _showPaymentConfirmedDialog();
            ref.invalidate(studentPaymentsProvider(widget.payment.studentId));
          }
        } catch (_) {}
      },
    );
  }

  void _showPaymentConfirmedDialog() {
    final sheetContext = context;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
              style:
                  AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Seu pagamento foi recebido com sucesso.',
              style: AppTheme.bodyMedium
                  .copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                if (mounted) Navigator.pop(sheetContext);
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

  Future<void> _generatePixPayment() async {
    final academyId = ref.read(selectedAcademyIdProvider) ?? '';

    try {
      final payIntent =
          await ref.read(tatami_repos.financialRepoProvider).payWithPix(
                academyId,
                widget.payment.id,
                body: api_fin.PayIntentRequest(
                  customerName: widget.studentName,
                ),
              );
      final link = PaymentLink(
        pixCode: payIntent.pixCopyPaste ?? '',
        qrCodeUrl: payIntent.pixQrCode,
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        abacatePayId: payIntent.externalId,
      );

      setState(() {
        _paymentLink = link;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Erro ao gerar pagamento: $e';
        _isLoading = false;
      });
    }
  }

  void _copyPixCode() {
    if (_paymentLink?.pixCode != null) {
      Clipboard.setData(ClipboardData(text: _paymentLink!.pixCode));
      context.showSuccess('Codigo PIX copiado!');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Pagar com PIX',
                style: AppTheme.titleLarge
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.payment.description ?? 'Mensalidade'} — ${formatCurrency(widget.payment.value)}',
                style: AppTheme.bodyMedium
                    .copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Gerando QR Code...'),
                    ],
                  ),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      const Icon(
                        LucideIcons.alertCircle,
                        size: 48,
                        color: AppTheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: AppTheme.bodyMedium
                            .copyWith(color: AppTheme.error),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else if (_paymentLink != null)
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: QrImageView(
                        data: _paymentLink!.pixCode,
                        version: QrVersions.auto,
                        size: 200,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Escaneie o QR Code ou copie o codigo PIX',
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _copyPixCode,
                        icon: const Icon(LucideIcons.copy, size: 18),
                        label: const Text('Copiar Codigo PIX'),
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _paymentConfirmed
                            ? AppTheme.successLight
                            : AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
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
                          Expanded(
                            child: Text(
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
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fechar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
