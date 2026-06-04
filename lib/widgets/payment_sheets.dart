import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:confetti/confetti.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme.dart';
import '../core/validators.dart';
import 'card_formatters.dart';
import '../services/firebase_service.dart';
import '../services/abacate_pay_service.dart';
import '../services/asaas_payment_service.dart';
import '../services/mercado_pago_service.dart';

// ============================================
// Modern PIX Payment Bottom Sheet
// ============================================
class PixPaymentSheet extends StatefulWidget {
  /// Pre-created PIX link. May be null when the sheet is responsible for
  /// generating it (see [requireCpf] / [onRegenerate]).
  final PaymentLink? paymentLink;
  final double amount;
  final String? orderId;
  final String? financialId;
  final String description;
  final VoidCallback? onPaymentConfirmed;
  final VoidCallback? onClose;

  /// Whether to prompt the payer for their CPF before generating the PIX.
  /// Set this true when the caller does NOT already have a CPF on file (e.g.
  /// Mercado Pago requires it). When true the sheet opens with [paymentLink]
  /// null-able via [onGenerateWithCpf]; the QR/code area shows a CPF form first.
  final bool requireCpf;

  /// Called with a validated, digits-only CPF when [requireCpf] is true and the
  /// payer submits the form. Should create the PIX (passing the CPF into the
  /// gateway call) and return the resulting [PaymentLink], or null/throw on
  /// failure. The sheet handles loading + friendly error states around it.
  final Future<PaymentLink?> Function(String cpf)? onGenerateWithCpf;

  /// Called when the payer taps "gerar novo" after the PIX expired (or to retry
  /// a failed generation). Should create a fresh [PaymentLink] and return it, or
  /// null/throw on failure. When [requireCpf] is true the previously captured
  /// CPF is passed back so the payer does not retype it.
  final Future<PaymentLink?> Function(String? cpf)? onRegenerate;

  const PixPaymentSheet({
    super.key,
    this.paymentLink,
    required this.amount,
    this.orderId,
    this.financialId,
    required this.description,
    this.onPaymentConfirmed,
    this.onClose,
    this.requireCpf = false,
    this.onGenerateWithCpf,
    this.onRegenerate,
  }) : assert(
          paymentLink != null || requireCpf || onRegenerate != null,
          'PixPaymentSheet needs a paymentLink, or requireCpf, or an onRegenerate callback to obtain one.',
        );

  @override
  State<PixPaymentSheet> createState() => _PixPaymentSheetState();
}

class _PixPaymentSheetState extends State<PixPaymentSheet>
    with SingleTickerProviderStateMixin {
  bool _paymentConfirmed = false;
  bool _copied = false;
  StreamSubscription<DocumentSnapshot>? _paymentListener;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Timer for PIX expiration
  Timer? _expirationTimer;
  Duration _timeRemaining = const Duration(hours: 24);

  /// The active PIX link. Starts from the widget but can be replaced by a
  /// CPF-driven generation or a regenerate-after-expiry.
  PaymentLink? _link;
  bool _expired = false;

  /// Captured CPF (digits-only) when [PixPaymentSheet.requireCpf] is true, so a
  /// later regenerate can reuse it.
  String? _capturedCpf;

  /// Busy while generating/regenerating a link.
  bool _generating = false;

  /// Friendly pt-BR error from a failed generation, with a retry affordance.
  String? _genError;

  final _cpfController = TextEditingController();
  final _cpfFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _link = widget.paymentLink;
    _setupAnimations();
    if (_link != null) {
      _setupPaymentListener();
      _startExpirationTimer();
    }
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
    _expirationTimer?.cancel();
    final link = _link;
    if (link == null) return;

    // Calculate remaining time from the active link's expiration (pixExpiresAt).
    final expiresAt = link.expiresAt;
    _timeRemaining = expiresAt.difference(DateTime.now());
    _expired = _timeRemaining.isNegative;

    _expirationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _timeRemaining = expiresAt.difference(DateTime.now());
        if (_timeRemaining.isNegative) {
          _expired = true;
          timer.cancel();
        }
      });
    });
  }

  void _setupPaymentListener() {
    final academyId = FirebaseService.academyId;

    String collection;
    String docId;

    if (widget.orderId != null) {
      collection = 'storeOrders';
      docId = widget.orderId!;
    } else if (widget.financialId != null) {
      collection = 'financials';
      docId = widget.financialId!;
    } else {
      return;
    }

    _paymentListener = FirebaseFirestore.instance
        .collection('academies')
        .doc(academyId)
        .collection(collection)
        .doc(docId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      final data = snapshot.data();
      final status = data?['status'] as String?;
      final isPaid = status == 'paid' ||
          (collection == 'financials' && data?['paymentDate'] != null);

      if (isPaid && !_paymentConfirmed) {
        setState(() => _paymentConfirmed = true);
        HapticFeedback.heavyImpact();
        _showSuccessDialog();
        if (mounted) widget.onPaymentConfirmed?.call();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _paymentListener?.cancel();
    _expirationTimer?.cancel();
    _cpfController.dispose();
    super.dispose();
  }

  /// Maps gateway/FirebaseFunctions errors to friendly pt-BR copy.
  String _friendlyError(Object error) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'unauthenticated':
          return 'Sessao expirada. Faca login novamente para gerar o PIX.';
        case 'permission-denied':
          return 'Sem permissao para gerar este pagamento.';
        case 'failed-precondition':
          return error.message ??
              'Pagamento indisponivel no momento. Tente novamente.';
        case 'invalid-argument':
          return error.message ?? 'Dados invalidos. Verifique e tente novamente.';
        case 'deadline-exceeded':
        case 'unavailable':
          return 'Servico indisponivel. Verifique sua conexao e tente novamente.';
        default:
          return error.message ?? 'Nao foi possivel gerar o PIX. Tente novamente.';
      }
    }
    return 'Nao foi possivel gerar o PIX. Tente novamente.';
  }

  /// Generates the first link from a submitted CPF (requireCpf flow).
  Future<void> _generateWithCpf() async {
    if (!(_cpfFormKey.currentState?.validate() ?? false)) return;
    final cpf = _cpfController.text.replaceAll(RegExp(r'\D'), '');
    _capturedCpf = cpf;
    final cb = widget.onGenerateWithCpf;
    if (cb == null) return;

    setState(() {
      _generating = true;
      _genError = null;
    });
    try {
      final link = await cb(cpf);
      if (!mounted) return;
      if (link == null) {
        setState(() {
          _generating = false;
          _genError = 'Nao foi possivel gerar o PIX. Tente novamente.';
        });
        return;
      }
      _adoptLink(link);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _genError = _friendlyError(e);
      });
    }
  }

  /// Regenerates the link after expiry or a failed generation.
  Future<void> _regenerate() async {
    final cb = widget.onRegenerate;
    if (cb == null) return;
    setState(() {
      _generating = true;
      _genError = null;
    });
    try {
      final link = await cb(_capturedCpf);
      if (!mounted) return;
      if (link == null) {
        setState(() {
          _generating = false;
          _genError = 'Nao foi possivel gerar um novo PIX. Tente novamente.';
        });
        return;
      }
      _adoptLink(link);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _genError = _friendlyError(e);
      });
    }
  }

  /// Adopts a freshly generated link: resets expiry/listener and shows the QR.
  void _adoptLink(PaymentLink link) {
    final hadLink = _link != null;
    setState(() {
      _link = link;
      _expired = false;
      _generating = false;
      _genError = null;
      _copied = false;
    });
    if (!hadLink) _setupPaymentListener();
    _startExpirationTimer();
  }

  Future<void> _openTicketUrl() async {
    final url = _link?.ticketUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _copyPixCode() {
    final link = _link;
    if (link == null) return;
    Clipboard.setData(ClipboardData(text: link.pixCode));
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
      pageBuilder: (dialogContext, __, ___) => _SuccessDialog(
        onClose: () {
          // Pop the dialog by ITS OWN route (never the sheet's State context),
          // then the sheet exactly once — guarded — so we never walk past the
          // navigator root (which blanked the screen / crashed).
          Navigator.of(dialogContext).pop();
          if (mounted) Navigator.of(context).pop();
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
                  _buildAmountCard()
                      .animate()
                      .fadeIn(delay: 60.ms, duration: 300.ms)
                      .slideY(begin: 0.08, curve: Curves.easeOut),
                  const SizedBox(height: 24),

                  ..._buildBody(),
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
          // Expiration timer (only while an active link is counting down)
          if (_link != null && !_expired)
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

  /// Chooses the central content depending on the current state:
  /// CPF capture form, generation error, expired affordance, or the QR/code.
  List<Widget> _buildBody() {
    // Generation error (failed create/regenerate) takes priority.
    if (_genError != null) {
      return [
        _buildErrorRetry()
            .animate()
            .fadeIn(duration: 250.ms)
            .slideY(begin: 0.08, curve: Curves.easeOut),
      ];
    }

    // No link yet and we need a CPF first.
    if (_link == null && widget.requireCpf) {
      return [
        _buildCpfCapture()
            .animate()
            .fadeIn(duration: 250.ms)
            .slideY(begin: 0.08, curve: Curves.easeOut),
      ];
    }

    // No link yet (regenerate-only entry) — show a generate affordance.
    if (_link == null) {
      return [
        _buildGeneratePrompt()
            .animate()
            .fadeIn(duration: 250.ms)
            .slideY(begin: 0.08, curve: Curves.easeOut),
      ];
    }

    // Expired — offer "gerar novo".
    if (_expired) {
      return [
        _buildExpired()
            .animate()
            .fadeIn(duration: 250.ms)
            .slideY(begin: 0.08, curve: Curves.easeOut),
      ];
    }

    // Active link — QR + copy + (optional) browser link + instructions.
    return [
      _buildQRCode()
          .animate()
          .fadeIn(delay: 140.ms, duration: 300.ms)
          .slideY(begin: 0.08, curve: Curves.easeOut),
      const SizedBox(height: 20),
      _buildCopyButton()
          .animate()
          .fadeIn(delay: 220.ms, duration: 300.ms)
          .slideY(begin: 0.08, curve: Curves.easeOut),
      if ((_link?.ticketUrl ?? '').isNotEmpty) ...[
        const SizedBox(height: 12),
        _buildTicketUrlButton()
            .animate()
            .fadeIn(delay: 260.ms, duration: 300.ms),
      ],
      const SizedBox(height: 20),
      _buildInstructions()
          .animate()
          .fadeIn(delay: 300.ms, duration: 300.ms)
          .slideY(begin: 0.08, curve: Curves.easeOut),
      const SizedBox(height: 20),
      _buildStatusIndicator()
          .animate()
          .fadeIn(delay: 380.ms, duration: 300.ms),
      const SizedBox(height: 16),
    ];
  }

  Widget _buildCpfCapture() {
    return Form(
      key: _cpfFormKey,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Informe seu CPF',
              style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Necessario para gerar o pagamento PIX.',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cpfController,
              keyboardType: TextInputType.number,
              inputFormatters: [CpfFormatter()],
              validator: Validators.cpf,
              decoration: InputDecoration(
                labelText: 'CPF',
                hintText: '000.000.000-00',
                prefixIcon: const Icon(LucideIcons.fileText, size: 20),
                filled: true,
                fillColor: AppTheme.surface,
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _generating ? null : _generateWithCpf,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _generating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Gerar PIX',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneratePrompt() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            'Gere o codigo PIX para pagar.',
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _generating ? null : _regenerate,
              icon: _generating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(LucideIcons.qrCode, size: 18),
              label: const Text('Gerar PIX'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpired() {
    final canRegenerate = widget.onRegenerate != null;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          const Icon(LucideIcons.clock, color: AppTheme.error, size: 32),
          const SizedBox(height: 12),
          Text(
            'Codigo PIX expirado',
            style: AppTheme.titleSmall.copyWith(
              color: AppTheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            canRegenerate
                ? 'O tempo para pagamento acabou. Gere um novo codigo.'
                : 'O tempo para pagamento acabou. Feche e tente novamente.',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
          if (canRegenerate) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _generating ? null : _regenerate,
                icon: _generating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.refreshCw, size: 18),
                label: const Text('Gerar novo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorRetry() {
    // Retry uses the same path that failed: CPF-driven generation if we still
    // have no link and requireCpf, otherwise regenerate.
    final useCpfRetry = _link == null &&
        widget.requireCpf &&
        widget.onGenerateWithCpf != null &&
        (_capturedCpf == null);
    final canRetry =
        useCpfRetry || widget.onRegenerate != null || _capturedCpf != null;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          const Icon(LucideIcons.alertCircle, color: AppTheme.error, size: 32),
          const SizedBox(height: 12),
          Text(
            _genError ?? 'Algo deu errado.',
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.error),
            textAlign: TextAlign.center,
          ),
          if (canRetry) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _generating
                    ? null
                    : () {
                        if (useCpfRetry) {
                          _generateWithCpf();
                        } else {
                          _regenerate();
                        }
                      },
                icon: _generating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.refreshCw, size: 18),
                label: const Text('Tentar novamente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTicketUrlButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _openTicketUrl,
        icon: const Icon(LucideIcons.externalLink, size: 18),
        label: const Text('Abrir pagina de pagamento'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primary,
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
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
            data: _link?.pixCode ?? '',
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
class _SuccessDialog extends StatefulWidget {
  final VoidCallback onClose;

  const _SuccessDialog({required this.onClose});

  @override
  State<_SuccessDialog> createState() => _SuccessDialogState();
}

class _SuccessDialogState extends State<_SuccessDialog> {
  late final ConfettiController _confetti;
  // Re-entrancy guard: a double-tap during the close transition must not fire
  // onClose twice (which would pop an extra route → black screen).
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _confetti =
        ConfettiController(duration: const Duration(seconds: 3))..play();
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Center(
          child: _buildCard(context),
        ),
        ConfettiWidget(
          confettiController: _confetti,
          blastDirectionality: BlastDirectionality.explosive,
          shouldLoop: false,
          maxBlastForce: 20,
          minBlastForce: 8,
          emissionFrequency: 0.05,
          numberOfParticles: 28,
          gravity: 0.15,
          colors: const [
            AppTheme.primary,
            AppTheme.success,
            AppTheme.warning,
            Color(0xFF7C3AED),
            Color(0xFFEC4899),
          ],
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context) {
    return Container(
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
                onPressed: _closing
                    ? null
                    : () {
                        setState(() => _closing = true);
                        widget.onClose();
                      },
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
      );
  }
}

// ============================================
// Modern Card Payment Sheet
// ============================================
class CardPaymentSheet extends StatefulWidget {
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
  State<CardPaymentSheet> createState() => _CardPaymentSheetState();
}

class _CardPaymentSheetState extends State<CardPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _cardNumberController = TextEditingController();
  final _cardHolderController = TextEditingController();
  final _expirationController = TextEditingController();
  final _cvvController = TextEditingController();
  final _cpfController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  String _cardBrand = '';
  int _installments = 1;

  @override
  void dispose() {
    _cardNumberController.dispose();
    _cardHolderController.dispose();
    _expirationController.dispose();
    _cvvController.dispose();
    _cpfController.dispose();
    super.dispose();
  }

  /// Installments chips (1x–6x). Applied to the Mercado Pago card charge.
  Widget _buildInstallmentsSelector() {
    final perInstallment = widget.amount / _installments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Parcelas',
          style: AppTheme.labelMedium.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: List.generate(6, (i) {
            final n = i + 1;
            final selected = _installments == n;
            return ChoiceChip(
              label: Text(n == 1 ? 'A vista' : '${n}x'),
              selected: selected,
              onSelected: (_) => setState(() => _installments = n),
            );
          }),
        ),
        const SizedBox(height: 6),
        Text(
          _installments == 1
              ? 'Pagamento a vista'
              : '$_installments x de R\$ ${perInstallment.toStringAsFixed(2)}',
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  /// Colored brand pill shown as the card-number field suffix.
  Widget _brandPill(String brand) {
    const colors = {
      'visa': Color(0xFF1A1F71),
      'mastercard': Color(0xFFEB001B),
      'amex': Color(0xFF2E77BC),
      'elo': Color(0xFF111111),
    };
    final label = {
      'visa': 'VISA',
      'mastercard': 'MASTER',
      'amex': 'AMEX',
      'elo': 'ELO',
    }[brand] ?? brand.toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors[brand] ?? AppTheme.textSecondary,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
    ).animate(key: ValueKey(brand)).fadeIn(duration: 200.ms).scaleXY(begin: 0.7);
  }

  String _detectCardBrand(String number) {
    final cleaned = number.replaceAll(' ', '');
    if (cleaned.startsWith('4')) return 'visa';
    if (cleaned.startsWith('5') || cleaned.startsWith('2')) return 'mastercard';
    if (cleaned.startsWith('3')) return 'amex';
    if (cleaned.startsWith('6')) return 'elo';
    return '';
  }


  /// Maps gateway/FirebaseFunctions errors to friendly pt-BR copy.
  String _friendlyCardError(Object error) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'unauthenticated':
          return 'Sessao expirada. Faca login novamente e tente de novo.';
        case 'permission-denied':
          return 'Sem permissao para realizar este pagamento.';
        case 'invalid-argument':
          return error.message ??
              'Dados invalidos. Verifique o cartao e tente novamente.';
        case 'failed-precondition':
          return error.message ??
              'Pagamento indisponivel no momento. Tente novamente.';
        case 'deadline-exceeded':
        case 'unavailable':
          return 'Servico indisponivel. Verifique sua conexao e tente novamente.';
        default:
          return error.message ??
              'Nao foi possivel processar o pagamento. Tente novamente.';
      }
    }
    return 'Nao foi possivel processar o pagamento. Tente novamente.';
  }

  Future<void> _handlePayment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final academyId = FirebaseService.academyId;

    try {
      final expParts = _expirationController.text.split('/');
      final cardData = CardData(
        cardNumber: _cardNumberController.text,
        cardHolder: _cardHolderController.text,
        expirationMonth: expParts[0],
        expirationYear: expParts.length > 1 ? expParts[1] : '',
        cvv: _cvvController.text,
        cpf: _cpfController.text,
      );

      // Gateway precedence: Mercado Pago (connected) > Asaas > AbacatePay.
      final mp = MercadoPagoService(academyId);
      final asaasService = AsaasPaymentService(academyId);
      final useMp = await mp.isEnabled();
      final isAsaas = !useMp && await asaasService.isEnabled();

      CardPaymentResult result;
      if (widget.orderId != null) {
        if (useMp) {
          result = await mp.createStoreOrderCardPayment(
            amount: widget.amount,
            orderId: widget.orderId!,
            studentId: widget.studentId,
            studentName: widget.studentName,
            cardData: cardData,
            description: widget.description,
            installments: _installments,
          );
        } else if (isAsaas) {
          result = await asaasService.createStoreOrderCardPayment(
            amount: widget.amount,
            orderId: widget.orderId!,
            studentId: widget.studentId,
            studentName: widget.studentName,
            cardData: cardData,
            description: widget.description,
          );
        } else {
          result = await AbacatePayService(academyId).createStoreOrderCardPayment(
            amount: widget.amount,
            orderId: widget.orderId!,
            studentId: widget.studentId,
            studentName: widget.studentName,
            cardData: cardData,
            description: widget.description,
          );
        }
      } else if (widget.financialId != null) {
        if (useMp) {
          result = await mp.createCardPayment(
            amount: widget.amount,
            financialId: widget.financialId!,
            studentId: widget.studentId,
            studentName: widget.studentName,
            cardData: cardData,
            description: widget.description,
            installments: _installments,
          );
        } else if (isAsaas) {
          result = await asaasService.createCardPayment(
            amount: widget.amount,
            financialId: widget.financialId!,
            studentId: widget.studentId,
            studentName: widget.studentName,
            cardData: cardData,
            description: widget.description,
          );
        } else {
          result = await AbacatePayService(academyId).createCardPayment(
            amount: widget.amount,
            financialId: widget.financialId!,
            studentId: widget.studentId,
            studentName: widget.studentName,
            cardData: cardData,
            description: widget.description,
          );
        }
      } else {
        throw Exception('Order ID or Financial ID is required');
      }

      if (result.success) {
        HapticFeedback.heavyImpact();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(LucideIcons.check, color: Colors.white, size: 18),
                  const SizedBox(width: 12),
                  Text(result.message ?? 'Pagamento aprovado!'),
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
      } else {
        setState(() {
          _errorMessage =
              result.message ?? 'Pagamento nao aprovado. Verifique os dados do cartao e tente novamente.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = _friendlyCardError(e);
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
                  inputFormatters: [CardNumberFormatter()],
                  onChanged: (value) =>
                      setState(() => _cardBrand = _detectCardBrand(value)),
                  validator: Validators.cardNumber,
                  suffix: _cardBrand.isEmpty ? null : _brandPill(_cardBrand),
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
                        inputFormatters: [ExpiryFormatter()],
                        validator: Validators.cardExpiration,
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
                        validator: Validators.cvv,
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
                  inputFormatters: [CpfFormatter()],
                  validator: Validators.cpf,
                ),
                const SizedBox(height: 20),

                // Installments selector (1x–6x).
                _buildInstallmentsSelector(),
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
                        : Text(
                            _errorMessage != null ? 'Tentar novamente' : 'Pagar Agora',
                            style: const TextStyle(
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
    Widget? suffix,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
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
