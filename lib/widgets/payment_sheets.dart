import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../api/dto/financial_dto.dart' as api_fin;
import '../api/repositories.dart' as tatami_repos;
import '../core/theme.dart';
import '../providers/selected_academy_provider.dart';
import '../services/abacate_pay_service.dart'; // PaymentLink type

// ============================================
// Modern PIX Payment Bottom Sheet
// ============================================
class PixPaymentSheet extends ConsumerStatefulWidget {
  final PaymentLink paymentLink;
  final double amount;
  final String? orderId;
  final String? financialId;
  final String description;
  final VoidCallback? onPaymentConfirmed;
  final VoidCallback? onClose;

  const PixPaymentSheet({
    super.key,
    required this.paymentLink,
    required this.amount,
    this.orderId,
    this.financialId,
    required this.description,
    this.onPaymentConfirmed,
    this.onClose,
  });

  @override
  ConsumerState<PixPaymentSheet> createState() => _PixPaymentSheetState();
}

class _PixPaymentSheetState extends ConsumerState<PixPaymentSheet>
    with SingleTickerProviderStateMixin {
  bool _paymentConfirmed = false;
  bool _copied = false;
  Timer? _paymentPollTimer;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Timer for PIX expiration
  Timer? _expirationTimer;
  Duration _timeRemaining = const Duration(hours: 24);

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _setupPaymentListener();
    _startExpirationTimer();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
  }

  void _startExpirationTimer() {
    // Calculate remaining time from paymentLink expiration
    final expiresAt = widget.paymentLink.expiresAt;
    _timeRemaining = expiresAt.difference(DateTime.now());

    _expirationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _timeRemaining = expiresAt.difference(DateTime.now());
        if (_timeRemaining.isNegative) {
          timer.cancel();
        }
      });
    });
  }

  /// Polls the Tatami API every 3 seconds to check if the payment status
  /// changed to "paid". Replaces the previous Firestore snapshots() listener
  /// since Tatami does not expose real-time streams for individual financials.
  ///
  /// Stops polling after payment confirmation or after 10 minutes (timeout).
  void _setupPaymentListener() {
    final academyId = ref.read(safeAcademyIdProvider) ?? '';

    // Only financials are supported for polling; store orders use a
    // different flow. If neither ID is present, skip.
    if (widget.financialId == null && widget.orderId == null) return;

    final isFinancial = widget.financialId != null;
    final docId = isFinancial ? widget.financialId! : widget.orderId!;

    // Timeout: stop polling after 10 minutes to avoid draining battery.
    final deadline = DateTime.now().add(const Duration(minutes: 10));

    _paymentPollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted || _paymentConfirmed) {
        timer.cancel();
        return;
      }

      if (DateTime.now().isAfter(deadline)) {
        timer.cancel();
        return;
      }

      try {
        if (isFinancial) {
          final repo = ref.read(tatami_repos.financialRepoProvider);
          final financial = await repo.getById(academyId, docId);
          final isPaid = financial.status == api_fin.ApiFinancialStatus.paid;

          if (isPaid && !_paymentConfirmed) {
            timer.cancel();
            if (!mounted) return;
            setState(() => _paymentConfirmed = true);
            HapticFeedback.heavyImpact();
            _showSuccessDialog();
            if (mounted) widget.onPaymentConfirmed?.call();
          }
        } else {
          // Store orders: poll via store repo
          final storeRepo = ref.read(tatami_repos.storeRepoProvider);
          final order = await storeRepo.getOrder(academyId, docId);
          final isPaid = order.status.name == 'paid';

          if (isPaid && !_paymentConfirmed) {
            timer.cancel();
            if (!mounted) return;
            setState(() => _paymentConfirmed = true);
            HapticFeedback.heavyImpact();
            _showSuccessDialog();
            if (mounted) widget.onPaymentConfirmed?.call();
          }
        }
      } catch (_) {
        // Swallow errors during polling — next tick will retry.
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _paymentPollTimer?.cancel();
    _expirationTimer?.cancel();
    super.dispose();
  }

  void _copyPixCode() {
    Clipboard.setData(ClipboardData(text: widget.paymentLink.pixCode));
    HapticFeedback.mediumImpact();
    setState(() => _copied = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(LucideIcons.check, color: Colors.white, size: 18),
            const SizedBox(width: 12),
            const Text('Codigo PIX copiado!'),
          ],
        ),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _showSuccessDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => _SuccessDialog(
        onClose: () {
          Navigator.pop(context); // Close dialog
          if (mounted) {
            Navigator.pop(context); // Close sheet
          }
          widget.onClose?.call();
        },
      ),
      transitionBuilder: (_, anim, __, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
    );
  }

  String _formatTimeRemaining() {
    if (_timeRemaining.isNegative) return 'Expirado';

    final hours = _timeRemaining.inHours;
    final minutes = _timeRemaining.inMinutes.remainder(60);
    final seconds = _timeRemaining.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  @override
  Widget build(BuildContext context) {
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
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
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
                  const SizedBox(height: 20),

                  // Header with gradient icon
                  _buildHeader(),
                  const SizedBox(height: 24),

                  // Amount Card
                  _buildAmountCard(),
                  const SizedBox(height: 24),

                  // QR Code with glow effect
                  _buildQRCode(),
                  const SizedBox(height: 20),

                  // Copy Code Button
                  _buildCopyButton(),
                  const SizedBox(height: 20),

                  // Instructions
                  _buildInstructions(),
                  const SizedBox(height: 20),

                  // Status Indicator
                  _buildStatusIndicator(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        // Gradient icon container
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primary,
                AppTheme.primary.withValues(alpha: 0.7),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            LucideIcons.qrCode,
            color: Colors.white,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pagar com PIX',
                style: AppTheme.headlineSmall.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.description,
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
          onPressed: () {
            Navigator.pop(context);
            widget.onClose?.call();
          },
          icon: const Icon(LucideIcons.x),
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.surfaceVariant,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAmountCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withValues(alpha: 0.08),
            AppTheme.primary.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Valor a pagar',
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'R\$ ${widget.amount.toStringAsFixed(2)}',
                style: AppTheme.headlineMedium.copyWith(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          // Expiration timer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _timeRemaining.inMinutes < 30
                  ? AppTheme.error.withValues(alpha: 0.1)
                  : AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.clock,
                  size: 14,
                  color: _timeRemaining.inMinutes < 30
                      ? AppTheme.error
                      : AppTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  _formatTimeRemaining(),
                  style: AppTheme.labelSmall.copyWith(
                    color: _timeRemaining.inMinutes < 30
                        ? AppTheme.error
                        : AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQRCode() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.1),
            blurRadius: 30,
            spreadRadius: 0,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          QrImageView(
            data: widget.paymentLink.pixCode,
            version: QrVersions.auto,
            size: 200,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Color(0xFF111111),
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Color(0xFF111111),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Escaneie com o app do banco',
            style: AppTheme.bodySmall.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCopyButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _copyPixCode,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Icon(
            _copied ? LucideIcons.check : LucideIcons.copy,
            key: ValueKey(_copied),
            size: 20,
          ),
        ),
        label: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            _copied ? 'Copiado!' : 'Copiar Codigo PIX',
            key: ValueKey(_copied),
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _copied ? AppTheme.success : AppTheme.textPrimary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _InstructionStep(number: 1, text: 'Abra o app do seu banco'),
          const SizedBox(height: 10),
          _InstructionStep(number: 2, text: 'Escolha pagar via PIX'),
          const SizedBox(height: 10),
          _InstructionStep(number: 3, text: 'Escaneie ou cole o codigo'),
          const SizedBox(height: 10),
          _InstructionStep(number: 4, text: 'Confirme o pagamento'),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _paymentConfirmed
              ? [AppTheme.success.withValues(alpha: 0.15), AppTheme.success.withValues(alpha: 0.05)]
              : [AppTheme.primary.withValues(alpha: 0.1), AppTheme.primary.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _paymentConfirmed
              ? AppTheme.success.withValues(alpha: 0.2)
              : AppTheme.primary.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_paymentConfirmed)
            const Icon(LucideIcons.checkCircle2, size: 20, color: AppTheme.success)
          else
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
            ),
          const SizedBox(width: 12),
          Text(
            _paymentConfirmed ? 'Pagamento confirmado!' : 'Aguardando pagamento...',
            style: AppTheme.bodyMedium.copyWith(
              color: _paymentConfirmed ? AppTheme.success : AppTheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Instruction Step Widget
// ============================================
class _InstructionStep extends StatelessWidget {
  final int number;
  final String text;

  const _InstructionStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$number',
              style: AppTheme.labelMedium.copyWith(
                color: AppTheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================
// Success Dialog
// ============================================
class _SuccessDialog extends StatelessWidget {
  final VoidCallback onClose;

  const _SuccessDialog({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated success icon
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.elasticOut,
              builder: (_, value, child) => Transform.scale(
                scale: value,
                child: child,
              ),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.success,
                      AppTheme.success.withValues(alpha: 0.7),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.success.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  LucideIcons.check,
                  size: 50,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Pagamento Confirmado!',
              style: AppTheme.headlineSmall.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Seu pagamento foi processado com sucesso.',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onClose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Continuar',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// Modern Card Payment Sheet
// ============================================
class CardPaymentSheet extends ConsumerStatefulWidget {
  final double amount;
  final String description;
  final String? orderId;
  final String? financialId;
  final String studentId;
  final String studentName;
  final VoidCallback? onPaymentSuccess;
  final VoidCallback? onClose;

  const CardPaymentSheet({
    super.key,
    required this.amount,
    required this.description,
    this.orderId,
    this.financialId,
    required this.studentId,
    required this.studentName,
    this.onPaymentSuccess,
    this.onClose,
  });

  @override
  ConsumerState<CardPaymentSheet> createState() => _CardPaymentSheetState();
}

class _CardPaymentSheetState extends ConsumerState<CardPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _cardNumberController = TextEditingController();
  final _cardHolderController = TextEditingController();
  final _expirationController = TextEditingController();
  final _cvvController = TextEditingController();
  final _cpfController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  String _cardBrand = '';

  @override
  void dispose() {
    _cardNumberController.dispose();
    _cardHolderController.dispose();
    _expirationController.dispose();
    _cvvController.dispose();
    _cpfController.dispose();
    super.dispose();
  }

  String _detectCardBrand(String number) {
    final cleaned = number.replaceAll(' ', '');
    if (cleaned.startsWith('4')) return 'visa';
    if (cleaned.startsWith('5') || cleaned.startsWith('2')) return 'mastercard';
    if (cleaned.startsWith('3')) return 'amex';
    if (cleaned.startsWith('6')) return 'elo';
    return '';
  }

  String _formatCardNumber(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < digitsOnly.length && i < 16; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digitsOnly[i]);
    }
    return buffer.toString();
  }

  String _formatExpiration(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length >= 2) {
      return '${digitsOnly.substring(0, 2)}/${digitsOnly.substring(2, digitsOnly.length.clamp(2, 4))}';
    }
    return digitsOnly;
  }

  String _formatCpf(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < digitsOnly.length && i < 11; i++) {
      if (i == 3 || i == 6) buffer.write('.');
      if (i == 9) buffer.write('-');
      buffer.write(digitsOnly[i]);
    }
    return buffer.toString();
  }

  Future<void> _handlePayment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final academyId = ref.read(safeAcademyIdProvider) ?? '';

    try {
      // Determina o financialId: orderId tem precedência, senão usa financialId.
      final financialId = widget.orderId ?? widget.financialId;
      if (financialId == null) {
        throw Exception('Order ID or Financial ID is required');
      }

      await ref.read(tatami_repos.financialRepoProvider).payWithCard(
            academyId,
            financialId,
            body: api_fin.PayIntentRequest(
              customerName: widget.studentName,
            ),
          );

      // Tatami: POST pay/card sem exceção = aprovado.
      HapticFeedback.heavyImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(LucideIcons.check, color: Colors.white, size: 18),
                const SizedBox(width: 12),
                const Text('Pagamento aprovado!'),
              ],
            ),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pop(context);
        widget.onPaymentSuccess?.call();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro ao processar pagamento: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.primary,
                            AppTheme.primary.withValues(alpha: 0.7),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        LucideIcons.creditCard,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pagar com Cartao',
                            style: AppTheme.headlineSmall.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'R\$ ${widget.amount.toStringAsFixed(2)}',
                            style: AppTheme.titleMedium.copyWith(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onClose?.call();
                      },
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

                // Error Message
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.alertCircle, color: AppTheme.error, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: AppTheme.bodySmall.copyWith(color: AppTheme.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Card Preview
                _buildCardPreview(),
                const SizedBox(height: 24),

                // Card Number
                _buildTextField(
                  controller: _cardNumberController,
                  label: 'Numero do Cartao',
                  hint: '0000 0000 0000 0000',
                  icon: LucideIcons.creditCard,
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    final formatted = _formatCardNumber(value);
                    if (formatted != value) {
                      _cardNumberController.value = TextEditingValue(
                        text: formatted,
                        selection: TextSelection.collapsed(offset: formatted.length),
                      );
                    }
                    setState(() => _cardBrand = _detectCardBrand(formatted));
                  },
                  validator: (value) {
                    if (value == null || value.replaceAll(' ', '').length < 16) {
                      return 'Numero invalido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Card Holder
                _buildTextField(
                  controller: _cardHolderController,
                  label: 'Nome no Cartao',
                  hint: 'COMO ESTA NO CARTAO',
                  icon: LucideIcons.user,
                  textCapitalization: TextCapitalization.characters,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Nome obrigatorio';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Expiration and CVV
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _expirationController,
                        label: 'Validade',
                        hint: 'MM/AA',
                        icon: LucideIcons.calendar,
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          final formatted = _formatExpiration(value);
                          if (formatted != value) {
                            _expirationController.value = TextEditingValue(
                              text: formatted,
                              selection: TextSelection.collapsed(offset: formatted.length),
                            );
                          }
                        },
                        validator: (value) {
                          if (value == null || !value.contains('/') || value.length < 5) {
                            return 'Invalido';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _cvvController,
                        label: 'CVV',
                        hint: '000',
                        icon: LucideIcons.lock,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        maxLength: 4,
                        validator: (value) {
                          if (value == null || value.length < 3) {
                            return 'Invalido';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // CPF
                _buildTextField(
                  controller: _cpfController,
                  label: 'CPF do Titular',
                  hint: '000.000.000-00',
                  icon: LucideIcons.fileText,
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    final formatted = _formatCpf(value);
                    if (formatted != value) {
                      _cpfController.value = TextEditingValue(
                        text: formatted,
                        selection: TextSelection.collapsed(offset: formatted.length),
                      );
                    }
                  },
                  validator: (value) {
                    if (value == null || value.replaceAll(RegExp(r'\D'), '').length < 11) {
                      return 'CPF invalido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 28),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handlePayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                      disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.5),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Pagar Agora',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                // Security Note
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.shieldCheck, size: 16, color: AppTheme.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      'Pagamento 100% seguro',
                      style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardPreview() {
    final cardNumber = _cardNumberController.text.isEmpty
        ? '**** **** **** ****'
        : _cardNumberController.text;
    final cardHolder = _cardHolderController.text.isEmpty
        ? 'SEU NOME'
        : _cardHolderController.text.toUpperCase();
    final expiration = _expirationController.text.isEmpty
        ? 'MM/AA'
        : _expirationController.text;

    return Container(
      height: 180,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A1A2E),
            const Color(0xFF16213E),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(LucideIcons.cpu, color: Colors.amber, size: 32),
              if (_cardBrand.isNotEmpty)
                Text(
                  _cardBrand.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
            ],
          ),
          Text(
            cardNumber,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              letterSpacing: 2,
              fontWeight: FontWeight.w500,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TITULAR',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cardHolder,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'VALIDADE',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    expiration,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    int? maxLength,
    TextCapitalization textCapitalization = TextCapitalization.none,
    void Function(String)? onChanged,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: AppTheme.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppTheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppTheme.error, width: 1),
        ),
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLength: maxLength,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      validator: validator,
    );
  }
}
