import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../services/subscription_service.dart';
import '../card_formatters.dart';

/// Bottom sheet showing the full state of a recurring card subscription, shared
/// by the admin and the portal financial screens. It only DECORATES the
/// server-owned subscription doc — the real boundary (cancel/pause/card swap and
/// term/dunning logic) lives in the Cloud Functions; this sheet just calls the
/// existing callables via [SubscriptionService].
///
/// Shows:
/// * status (with `completed` distinct from `cancelled`),
/// * term progress `chargesPaid/months` (open-ended when `months==0`),
/// * next billing date + monthly value,
/// * the non-PCI card mirror (`•••• 1234`, `MM/AA`) + dunning state,
/// * the settled-cycle history (academy `financials` filtered by
///   `subscriptionId`),
/// * actions: Pausar / Cancelar / Trocar cartão.
class SubscriptionDetailSheet extends StatelessWidget {
  final Subscription sub;
  final String academyId;

  /// Whether to expose the management actions (cancel/pause/change-card). The
  /// portal passes `true` for the student's own subscription; the admin may pass
  /// `false` for a read-only view. Defaults to `true`.
  final bool canManage;

  /// Called after a successful cancel/pause/card-update so the caller can
  /// invalidate its providers (the live stream usually refreshes on its own, but
  /// callers may need to refetch dependent data).
  final VoidCallback? onChanged;

  const SubscriptionDetailSheet({
    super.key,
    required this.sub,
    required this.academyId,
    this.canManage = true,
    this.onChanged,
  });

  /// Opens the sheet modally. Convenience used by both screens.
  static Future<void> show(
    BuildContext context, {
    required Subscription sub,
    required String academyId,
    bool canManage = true,
    VoidCallback? onChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SubscriptionDetailSheet(
        sub: sub,
        academyId: academyId,
        canManage: canManage,
        onChanged: onChanged,
      ),
    );
  }

  ({String label, Color color}) get _statusChip {
    switch (sub.status) {
      case 'authorized':
      case 'pending':
        return (label: 'Ativa', color: AppTheme.success);
      case 'paused':
        return (label: 'Pausada', color: AppTheme.warning);
      case 'completed':
        return (label: 'Concluída', color: AppTheme.info);
      case 'cancelled':
        return (label: 'Cancelada', color: AppTheme.textSecondary);
      default:
        return (label: 'Encerrada', color: AppTheme.textSecondary);
    }
  }

  bool get _isManageable =>
      canManage &&
      (sub.status == 'authorized' ||
          sub.status == 'pending' ||
          sub.status == 'paused');

  @override
  Widget build(BuildContext context) {
    final chip = _statusChip;
    final df = DateFormat('dd/MM/yyyy');
    final currency =
        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                  const Icon(LucideIcons.repeat,
                      size: 20, color: AppTheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Assinatura',
                      style: AppTheme.titleLarge
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: chip.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      chip.label,
                      style: AppTheme.labelSmall.copyWith(
                          color: chip.color, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Value + next charge
              Text(
                '${currency.format(sub.recurringValue)} / mês',
                style: AppTheme.headlineSmall
                    .copyWith(fontWeight: FontWeight.w700),
              ),
              if (sub.nextBillingDate != null &&
                  sub.status != 'completed' &&
                  sub.status != 'cancelled') ...[
                const SizedBox(height: 4),
                Text(
                  'Próxima cobrança em ${df.format(sub.nextBillingDate!)}',
                  style: AppTheme.bodySmall
                      .copyWith(color: AppTheme.textSecondary),
                ),
              ],
              const SizedBox(height: 16),

              _ProgressBlock(sub: sub),

              if (sub.status == 'completed') ...[
                const SizedBox(height: 12),
                _InfoBanner(
                  icon: LucideIcons.checkCircle,
                  color: AppTheme.info,
                  text:
                      'Assinatura concluída — os ${sub.months} meses contratados '
                      'foram cobrados. Não há renovação automática.',
                ),
              ],

              if (sub.needsReauth) ...[
                const SizedBox(height: 12),
                _InfoBanner(
                  icon: LucideIcons.alertTriangle,
                  color: AppTheme.error,
                  text: sub.failedAttempts > 0
                      ? 'Cobrança recusada (${sub.failedAttempts}ª tentativa). '
                          'Atualize o cartão para retomar a assinatura.'
                      : 'Cobrança recusada. Atualize o cartão para retomar a '
                          'assinatura.',
                ),
              ],

              // Card mirror
              if (sub.maskedCard != null) ...[
                const SizedBox(height: 16),
                _CardRow(
                  masked: sub.maskedCard!,
                  expiry: sub.cardExpiryLabel,
                ),
              ],

              const SizedBox(height: 20),

              // Settled-cycle history
              Text(
                'Histórico de cobranças',
                style:
                    AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              _CycleHistory(
                academyId: academyId,
                subscriptionId: sub.id,
                currency: currency,
              ),

              if (_isManageable) ...[
                const SizedBox(height: 20),
                _Actions(
                  sub: sub,
                  academyId: academyId,
                  onChanged: onChanged,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBlock extends StatelessWidget {
  final Subscription sub;
  const _ProgressBlock({required this.sub});

  @override
  Widget build(BuildContext context) {
    if (sub.months <= 0) {
      return Row(
        children: [
          const Icon(LucideIcons.infinity,
              size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Text(
            'Assinatura sem prazo final · ${sub.chargesPaid} cobrança(s) realizada(s)',
            style:
                AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      );
    }
    final paid = sub.chargesPaid.clamp(0, sub.months);
    final fraction = sub.months == 0 ? 0.0 : paid / sub.months;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Progresso',
              style: AppTheme.labelMedium
                  .copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              '$paid de ${sub.months} cobranças',
              style: AppTheme.labelSmall
                  .copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: AppTheme.surfaceVariant,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppTheme.primary),
          ),
        ),
      ],
    );
  }
}

class _CardRow extends StatelessWidget {
  final String masked;
  final String? expiry;
  const _CardRow({required this.masked, this.expiry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.creditCard,
              size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 10),
          Text(
            masked,
            style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (expiry != null)
            Text(
              'Val. $expiry',
              style: AppTheme.labelSmall
                  .copyWith(color: AppTheme.textSecondary),
            ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InfoBanner(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTheme.labelSmall.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _CycleHistory extends StatelessWidget {
  final String academyId;
  final String subscriptionId;
  final NumberFormat currency;

  const _CycleHistory({
    required this.academyId,
    required this.subscriptionId,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    return StreamBuilder<List<SubscriptionCharge>>(
      stream:
          SubscriptionService(academyId).streamCycleHistory(subscriptionId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final charges = snap.data ?? const <SubscriptionCharge>[];
        if (charges.isEmpty) {
          return Text(
            'Nenhuma cobrança liquidada ainda.',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          );
        }
        return Column(
          children: [
            for (final c in charges)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.successLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(LucideIcons.checkCircle,
                          size: 16, color: AppTheme.success),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.cycle != null
                                ? 'Cobrança ${c.cycle}'
                                : 'Cobrança',
                            style: AppTheme.bodySmall
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            [
                              if (c.referenceMonth != null) c.referenceMonth!,
                              if (c.paidAt != null) df.format(c.paidAt!),
                            ].join(' · '),
                            style: AppTheme.labelSmall
                                .copyWith(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      currency.format(c.amount),
                      style: AppTheme.bodySmall
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Actions extends StatefulWidget {
  final Subscription sub;
  final String academyId;
  final VoidCallback? onChanged;

  const _Actions({
    required this.sub,
    required this.academyId,
    this.onChanged,
  });

  @override
  State<_Actions> createState() => _ActionsState();
}

class _ActionsState extends State<_Actions> {
  bool _busy = false;

  SubscriptionService get _service => SubscriptionService(widget.academyId);

  Future<void> _run(
    Future<void> Function() action, {
    required String success,
    String? confirmTitle,
    String? confirmBody,
  }) async {
    if (confirmTitle != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(confirmTitle),
          content: confirmBody != null ? Text(confirmBody) : null,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );
      // The confirm dialog is an async gap: the parent bottom sheet may have
      // been dismissed (drag-down / pop) while it was open, disposing this
      // State. Guard before touching setState/context.
      if (!mounted) return;
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      widget.onChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success), backgroundColor: AppTheme.success),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível concluir: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _changeCard() async {
    final changed = await UpdateSubscriptionCardSheet.show(
      context,
      academyId: widget.academyId,
      subscriptionId: widget.sub.id,
    );
    if (!mounted) return;
    if (changed == true) {
      widget.onChanged?.call();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final paused = widget.sub.status == 'paused';
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _changeCard,
            icon: const Icon(LucideIcons.creditCard, size: 18),
            label: Text(
              widget.sub.needsReauth ? 'Atualizar cartão' : 'Trocar cartão',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (!paused)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                            () => _service.pause(widget.sub.id),
                            success: 'Assinatura pausada.',
                            confirmTitle: 'Pausar assinatura?',
                            confirmBody:
                                'As próximas cobranças ficam suspensas até você '
                                'retomar. Nenhum mês já pago é perdido.',
                          ),
                  icon: const Icon(LucideIcons.pause, size: 16),
                  label: const Text('Pausar'),
                ),
              ),
            if (!paused) const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(
                          () => _service.cancel(widget.sub.id),
                          success: 'Assinatura cancelada.',
                          confirmTitle: 'Cancelar assinatura?',
                          confirmBody:
                              'As próximas cobranças serão interrompidas. Os '
                              'meses já pagos permanecem. Sem reembolso do mês '
                              'corrente.',
                        ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  side: BorderSide(
                      color: AppTheme.error.withValues(alpha: 0.5)),
                ),
                icon: const Icon(LucideIcons.x, size: 16),
                label: const Text('Cancelar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Compact card-capture sheet that swaps the card backing a subscription. It
/// tokenizes the card client-side (PCI-safe, via [SubscriptionService.updateCard]
/// → [MpCardTokenizer]) and calls the `updateSubscriptionCard` callable; the
/// server re-authorizes the preapproval and clears the dunning state. Pops with
/// `true` on success.
class UpdateSubscriptionCardSheet extends StatefulWidget {
  final String academyId;
  final String subscriptionId;

  /// Called after the card was successfully updated (in addition to the sheet
  /// popping with `true`). Lets callers that don't read the pop result still
  /// refresh their providers.
  final VoidCallback? onUpdated;

  const UpdateSubscriptionCardSheet({
    super.key,
    required this.academyId,
    required this.subscriptionId,
    this.onUpdated,
  });

  /// Opens the card-update sheet modally. Returns `true` when the card was
  /// updated. Convenience used by the dunning banner / detail actions.
  static Future<bool?> show(
    BuildContext context, {
    required String academyId,
    required String subscriptionId,
    VoidCallback? onUpdated,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UpdateSubscriptionCardSheet(
        academyId: academyId,
        subscriptionId: subscriptionId,
        onUpdated: onUpdated,
      ),
    );
  }

  @override
  State<UpdateSubscriptionCardSheet> createState() =>
      _UpdateSubscriptionCardSheetState();
}

class _UpdateSubscriptionCardSheetState
    extends State<UpdateSubscriptionCardSheet> {
  final _formKey = GlobalKey<FormState>();
  final _cardNumberController = TextEditingController();
  final _cardHolderController = TextEditingController();
  final _expirationController = TextEditingController();
  final _cvvController = TextEditingController();
  final _cpfController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _cardNumberController.dispose();
    _cardHolderController.dispose();
    _expirationController.dispose();
    _cvvController.dispose();
    _cpfController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final expParts = _expirationController.text.split('/');
      await SubscriptionService(widget.academyId).updateCard(
        subscriptionId: widget.subscriptionId,
        cardNumber: _cardNumberController.text,
        expirationMonth: expParts[0].trim(),
        expirationYear: expParts.length > 1 ? expParts[1].trim() : '',
        securityCode: _cvvController.text,
        cardholderName: _cardHolderController.text,
        cpf: _cpfController.text,
      );
      if (!mounted) return;
      widget.onUpdated?.call();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Não foi possível atualizar o cartão. Verifique os dados e '
            'tente novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                Text(
                  'Trocar cartão',
                  style:
                      AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'O novo cartão passa a ser cobrado nas próximas mensalidades.',
                  style: AppTheme.bodySmall
                      .copyWith(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 20),
                _field(
                  controller: _cardNumberController,
                  label: 'Número do cartão',
                  hint: '0000 0000 0000 0000',
                  keyboardType: TextInputType.number,
                  inputFormatters: [CardNumberFormatter()],
                  validator: (v) {
                    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                    if (digits.length < 13) return 'Número inválido';
                    return null;
                  },
                ),
                _field(
                  controller: _cardHolderController,
                  label: 'Nome no cartão',
                  hint: 'Como impresso no cartão',
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        controller: _expirationController,
                        label: 'Validade',
                        hint: 'MM/AA',
                        keyboardType: TextInputType.number,
                        inputFormatters: [ExpiryFormatter()],
                        validator: (v) =>
                            (v == null || v.length < 5) ? 'MM/AA' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        controller: _cvvController,
                        label: 'CVV',
                        hint: '123',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        validator: (v) =>
                            (v == null || v.length < 3) ? 'CVV' : null,
                      ),
                    ),
                  ],
                ),
                _field(
                  controller: _cpfController,
                  label: 'CPF do titular',
                  hint: '000.000.000-00',
                  keyboardType: TextInputType.number,
                  inputFormatters: [CpfFormatter()],
                  validator: (v) {
                    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                    if (digits.length != 11) return 'CPF inválido';
                    return null;
                  },
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    style: AppTheme.labelSmall.copyWith(color: AppTheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Salvar cartão'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.labelMedium.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            textCapitalization: textCapitalization,
            validator: validator,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: AppTheme.surfaceVariant,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
