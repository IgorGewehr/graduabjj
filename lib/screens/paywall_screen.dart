import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/fns.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/academy.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/firebase_service.dart';
import '../widgets/polish/polish.dart';

enum _BillingPlan { mensal, trimestral, anual }

class PaywallScreen extends ConsumerStatefulWidget {
  /// When true, shows a close button at the top — used when the paywall is
  /// opened voluntarily (e.g. from the trial banner) so the user can dismiss
  /// it. As the access gate (rendered inline by AdminShell) it stays false so
  /// there's no escape until the academy regains access.
  final bool showClose;

  /// When true, frames the screen as "pagamento recusado / atualize o cartão"
  /// (renovação recorrente que falhou) em vez do paywall genérico de trial.
  final bool pastDue;

  const PaywallScreen({
    super.key,
    this.showClose = false,
    this.pastDue = false,
  });

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  _BillingPlan _selected = _BillingPlan.anual;
  bool _launching = false;
  bool _checking = false;

  static const _plans = [
    _PlanData(
      key: _BillingPlan.mensal,
      label: 'Mensal',
      price: 89.99,
      period: 'mês',
      monthlyEquivalent: 89.99,
      description: null,
      savingsPct: null,
      isPopular: false,
    ),
    _PlanData(
      key: _BillingPlan.trimestral,
      label: 'Trimestral',
      price: 224.99,
      period: 'trimestre',
      monthlyEquivalent: 74.99,
      description: 'R\$ 74,99/mês',
      savingsPct: 17,
      isPopular: false,
    ),
    _PlanData(
      key: _BillingPlan.anual,
      label: 'Anual',
      price: 854.99,
      period: 'ano',
      monthlyEquivalent: 71.25,
      description: 'R\$ 71,25/mês',
      savingsPct: 21,
      isPopular: true,
    ),
  ];

  String get _planKey => switch (_selected) {
        _BillingPlan.mensal => 'mensal',
        _BillingPlan.trimestral => 'trimestral',
        _BillingPlan.anual => 'anual',
      };

  /// Whether the 50%-off-first-month promo applies right now: the academy is in
  /// trial, within the first [AppConstants.promoFirstDays] days, and a promo
  /// coupon is configured. (Applies to the Mensal plan only.)
  // Regra movida para o modelo (AcademySubscription.isFirstMonthPromoEligible),
  // onde é testável. Mantido como wrapper pra não mexer nos call sites.
  bool _isPromoEligible(AcademySubscription? sub) =>
      sub?.isFirstMonthPromoEligible ?? false;

  /// Cria o checkout no Mercado Pago (via Cloud Function `createMercadoPagoCheckout`)
  /// e abre a URL hospedada (init_point) no navegador. [recurring] true =
  /// assinatura que renova sozinha; false = pagamento avulso (Pix/boleto/cartão
  /// à vista). O período vem do plano selecionado; a função usa o academyId no
  /// `external_reference` pra o webhook liberar o acesso depois.
  Future<void> _openCheckout({required bool recurring}) async {
    final academyId = ref.read(currentUserProvider).valueOrNull?.academyId;
    if (academyId == null || academyId.isEmpty) {
      _showError();
      return;
    }
    setState(() => _launching = true);
    try {
      final result = await Fns.functions
          .httpsCallable('createMercadoPagoCheckout')
          .call(<String, dynamic>{
        'academyId': academyId,
        'plan': _planKey,
        'recurring': recurring,
      });
      final initPoint = (result.data as Map?)?['initPoint'] as String?;
      if (initPoint == null || initPoint.isEmpty) {
        if (mounted) _showError();
        return;
      }
      final ok = await launchUrl(
        Uri.parse(initPoint),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) _showError();
    } catch (_) {
      if (mounted) _showError();
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  Future<void> _openWhatsApp() async {
    final uri = Uri.parse(AppConstants.supportWhatsApp);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// "Já paguei": re-checa a assinatura por até ~30s (a cada 3s, lendo o doc no
  /// servidor) aguardando o webhook gravar o `paidUntil`. Assim que confirma,
  /// invalida o provider — o gate do AdminShell some sozinho. Se estourar o
  /// tempo, avisa que ainda está processando.
  Future<void> _checkPayment() async {
    final academyId = ref.read(currentUserProvider).valueOrNull?.academyId;
    if (academyId == null) return;

    setState(() => _checking = true);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    var confirmed = false;

    while (mounted && DateTime.now().isBefore(deadline)) {
      try {
        final snap = await FirebaseService.firestore
            .collection('academies')
            .doc(academyId)
            .get(const GetOptions(source: Source.server));
        final subMap = snap.data()?['subscription'] as Map<String, dynamic>?;
        final sub = subMap != null ? AcademySubscription.fromMap(subMap) : null;
        // Confirma especificamente o PAGAMENTO (paidUntil futuro) — não o trial.
        if (sub?.paidUntil != null &&
            sub!.paidUntil!.isAfter(DateTime.now())) {
          confirmed = true;
          break;
        }
      } catch (_) {
        // erro de rede transitório — tenta de novo no próximo ciclo
      }
      await Future.delayed(const Duration(seconds: 3));
    }

    if (!mounted) return;
    setState(() => _checking = false);

    if (confirmed) {
      ref.invalidate(subscriptionProvider);
      if (widget.showClose) Navigator.of(context).maybePop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pagamento ainda não confirmado. Aguarde alguns instantes e toque novamente.',
          ),
        ),
      );
    }
  }

  void _showError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Não foi possível abrir o checkout. Tente novamente.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sub = ref.watch(subscriptionProvider).valueOrNull;
    final isTrialing = sub?.isTrialing ?? false;
    final daysLeft = sub?.trialDaysLeft ?? 0;
    final promoEligible = _isPromoEligible(sub);
    final selectedPlan = _plans.firstWhere((p) => p.key == _selected);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.showClose)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(LucideIcons.x),
                          color: AppTheme.textSecondary,
                          tooltip: 'Fechar',
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 48),

                  // Header
                  _Header(
                    isTrialing: isTrialing,
                    daysLeft: daysLeft,
                    pastDue: widget.pastDue,
                  ).fadeInQuick(),

                  const SizedBox(height: 32),

                  // 50%-off-1º-mês promo banner (only when eligible). Relocated
                  // above the grid so the (future) promo isn't lost. No logic
                  // change — driven by the same `promoEligible` flag.
                  if (promoEligible) ...[
                    const _PromoBanner().entrance(index: 0),
                    const SizedBox(height: 16),
                  ],

                  // Plan selector
                  ..._plans.asMap().entries.map((entry) {
                    final plan = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PlanCard(
                        plan: plan,
                        isSelected: _selected == plan.key,
                        // 1º mês com 50% off — só no Mensal e dentro da janela.
                        promoPrice:
                            (promoEligible && plan.key == _BillingPlan.mensal)
                                ? plan.price / 2
                                : null,
                        onTap: () => setState(() => _selected = plan.key),
                      ).entrance(index: entry.key + 1),
                    );
                  }),

                  const SizedBox(height: 12),

                  // Features list
                  const _FeatureList().entrance(index: 4),

                  const SizedBox(height: 16),

                  // Trust signals
                  const _TrustRow().entrance(index: 5),

                  const SizedBox(height: 28),

                  // CTA button — assinatura recorrente (renova sozinha)
                  _CtaButton(
                    plan: selectedPlan,
                    loading: _launching,
                    onTap: () => _openCheckout(recurring: true),
                  ).entrance(index: 6),

                  const SizedBox(height: 12),

                  // Pagamento avulso — Pix/boleto/cartão à vista (não renova).
                  // Promovido de texto cinza para botão outlined (Pix é via
                  // primária de pagamento no BR).
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _launching
                          ? null
                          : () => _openCheckout(recurring: false),
                      icon: const Icon(LucideIcons.qrCode, size: 18),
                      label: const Text('Pagar à vista (Pix ou boleto)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textPrimary,
                        side: const BorderSide(color: AppTheme.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ).entrance(index: 6),

                  const SizedBox(height: 12),

                  // WhatsApp support
                  TextButton.icon(
                    onPressed: _openWhatsApp,
                    icon: const Icon(LucideIcons.messageCircle, size: 16),
                    label: const Text('Falar com suporte'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      textStyle: const TextStyle(fontSize: 14),
                    ),
                  ).fadeInQuick(),

                  const SizedBox(height: 4),

                  // Already paid
                  TextButton(
                    onPressed: _checking ? null : _checkPayment,
                    child: _checking
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Verificando pagamento...',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          )
                        : const Text(
                            'Já paguei — atualizar acesso',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                  ).fadeInQuick(),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final bool isTrialing;
  final int daysLeft;
  final bool pastDue;

  const _Header({
    required this.isTrialing,
    required this.daysLeft,
    this.pastDue = false,
  });

  @override
  Widget build(BuildContext context) {
    final String title;
    final String subtitle;
    if (pastDue) {
      title = 'Não conseguimos renovar sua assinatura';
      subtitle =
          'Houve um problema na cobrança recorrente. Atualize seu pagamento abaixo para manter o BJJEasy ativo na sua academia.';
    } else if (isTrialing) {
      title = 'Continue gerenciando sua academia sem interrupções';
      subtitle =
          'Escolha um plano e mantenha graduações, turmas e cobranças funcionando sem perder nada.';
    } else {
      title = 'Período de avaliação encerrado';
      subtitle =
          'Assine para reativar o acesso a todos os recursos do BJJEasy. Seus dados continuam guardados.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Logo
        Image.asset(
          'assets/images/bjjeasy_logo.png',
          height: 72,
        ),
        const SizedBox(height: 20),

        // Trial countdown badge — shown whenever trialing (not only ≤3 days).
        if (isTrialing && !pastDue) ...[
          _CountdownBadge(daysLeft: daysLeft),
          const SizedBox(height: 16),
        ],

        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
            letterSpacing: -0.5,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),

        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            color: AppTheme.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _CountdownBadge extends StatelessWidget {
  final int daysLeft;

  const _CountdownBadge({required this.daysLeft});

  @override
  Widget build(BuildContext context) {
    final urgent = daysLeft <= 3;
    final label = daysLeft <= 0
        ? 'Último dia de avaliação'
        : 'Avaliação grátis · $daysLeft dia${daysLeft != 1 ? 's' : ''} restante${daysLeft != 1 ? 's' : ''}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: urgent ? AppTheme.warningLight : AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: urgent ? AppTheme.warning : AppTheme.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.clock,
            size: 13,
            color: urgent ? AppTheme.warning : AppTheme.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: urgent ? AppTheme.warning : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Promo banner (50% off 1º mês) — relocated above the plan grid.
// ---------------------------------------------------------------------------

class _PromoBanner extends StatelessWidget {
  const _PromoBanner();

  @override
  Widget build(BuildContext context) {
    return PolishCard(
      radius: 14,
      color: AppTheme.successLight,
      border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const Icon(LucideIcons.tag, size: 18, color: AppTheme.success),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Oferta de boas-vindas: 50% de desconto no 1º mês do plano Mensal.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Plan Card
// ---------------------------------------------------------------------------

class _PlanCard extends StatelessWidget {
  final _PlanData plan;
  final bool isSelected;
  final VoidCallback onTap;

  /// When set, shows the 50%-off first-month promo: badge + this discounted
  /// price with the original [plan.price] struck through.
  final double? promoPrice;

  const _PlanCard({
    required this.plan,
    required this.isSelected,
    required this.onTap,
    this.promoPrice,
  });

  /// Annualized monthly the buyer *would* pay at the Mensal rate, for an
  /// honest struck-through anchor. Computed only from existing constants.
  static const double _mensalMonthly = 89.99;

  /// Concrete yearly savings vs paying the Mensal rate for the same period.
  String? get _concreteSavings {
    if (plan.savingsPct == null) return null;
    switch (plan.key) {
      case _BillingPlan.trimestral:
        final full = _mensalMonthly * 3;
        return 'economize R\$ ${_fmt(full - plan.price)}';
      case _BillingPlan.anual:
        final full = _mensalMonthly * 12;
        return 'economize R\$ ${_fmt(full - plan.price)}/ano';
      case _BillingPlan.mensal:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final onAccent = isSelected ? Colors.white : AppTheme.textPrimary;
    final onAccentMuted = isSelected
        ? Colors.white.withValues(alpha: 0.7)
        : AppTheme.textSecondary;

    final card = PolishCard(
      radius: 16,
      elevated: isSelected,
      color: isSelected ? AppTheme.textPrimary : AppTheme.surface,
      border: isSelected
          ? null
          : Border.all(
              color: plan.isPopular ? AppTheme.textPrimary : AppTheme.border,
              width: plan.isPopular ? 1.5 : 1,
            ),
      padding: EdgeInsets.fromLTRB(18, plan.isPopular ? 18 : 16, 18, 16),
      child: Row(
        children: [
          // Selection indicator
          _RadioDot(isSelected: isSelected),
          const SizedBox(width: 14),

          // Plan info (label + monthly equivalent as the hero number)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: onAccentMuted,
                  ),
                ),
                const SizedBox(height: 4),
                // Lead with the reassuring monthly figure.
                _MonthlyHero(
                  plan: plan,
                  promoPrice: promoPrice,
                  onAccent: onAccent,
                  onAccentMuted: onAccentMuted,
                ),
                const SizedBox(height: 2),
                // Period total as a small caption (less prominent).
                Text(
                  promoPrice != null
                      ? 'depois R\$ ${_fmt(plan.price)}/${plan.period}'
                      : _periodCaption,
                  style: TextStyle(
                    fontSize: 12,
                    color: onAccentMuted,
                  ),
                ),
              ],
            ),
          ),

          // Savings / promo badges
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (promoPrice != null)
                _Pill(
                  text: '-50% 1º mês',
                  bg: isSelected
                      ? Colors.white.withValues(alpha: 0.2)
                      : AppTheme.success,
                  fg: Colors.white,
                )
              else if (_concreteSavings != null) ...[
                _Pill(
                  text: _concreteSavings!,
                  bg: isSelected
                      ? Colors.white.withValues(alpha: 0.15)
                      : AppTheme.successLight,
                  fg: isSelected ? Colors.white : AppTheme.success,
                ),
                if (plan.key != _BillingPlan.mensal) ...[
                  const SizedBox(height: 4),
                  // Honest struck-through monthly anchor (89,99 → equiv).
                  Text(
                    'R\$ ${_fmt(_mensalMonthly)}/mês',
                    style: TextStyle(
                      fontSize: 11,
                      decoration: TextDecoration.lineThrough,
                      color: onAccentMuted,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ],
      ),
    );

    final body = plan.isPopular
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top-edge ribbon for the recommended plan.
              Container(
                margin: const EdgeInsets.only(left: 18, right: 18, bottom: -4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: const BoxDecoration(
                  color: AppTheme.textPrimary,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.star, size: 11, color: Colors.white),
                    SizedBox(width: 5),
                    Text(
                      'MAIS POPULAR',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              card,
            ],
          )
        : card;

    return Semantics(
      button: true,
      selected: isSelected,
      label:
          '${plan.label}, ${plan.description ?? 'R\$ ${_fmt(plan.price)} por ${plan.period}'}'
          '${plan.isPopular ? ', plano recomendado' : ''}',
      child: Pressable(onTap: onTap, child: body),
    );
  }

  String get _periodCaption {
    final word = plan.key == _BillingPlan.mensal
        ? 'cobrado mensalmente'
        : plan.key == _BillingPlan.trimestral
            ? 'R\$ ${_fmt(plan.price)} cobrado trimestralmente'
            : 'R\$ ${_fmt(plan.price)} cobrado anualmente';
    return word;
  }

  String _fmt(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
}

/// The hero monthly figure inside a plan card. For the promo case it shows the
/// discounted first-month price; otherwise the plan's monthly equivalent.
class _MonthlyHero extends StatelessWidget {
  final _PlanData plan;
  final double? promoPrice;
  final Color onAccent;
  final Color onAccentMuted;

  const _MonthlyHero({
    required this.plan,
    required this.promoPrice,
    required this.onAccent,
    required this.onAccentMuted,
  });

  String _fmt(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final value = promoPrice ?? plan.monthlyEquivalent;
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'R\$ ${_fmt(value)}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: onAccent,
              letterSpacing: -0.5,
            ),
          ),
          TextSpan(
            text: promoPrice != null ? ' 1º mês' : ' /mês',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: onAccentMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  final bool isSelected;

  const _RadioDot({required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? Colors.white : AppTheme.textDisabled,
          width: 2,
        ),
        color: isSelected ? Colors.white : Colors.transparent,
      ),
      child: isSelected
          ? Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.textPrimary,
                ),
              ),
            )
          : null,
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;

  const _Pill({required this.text, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feature list
// ---------------------------------------------------------------------------

class _FeatureList extends StatelessWidget {
  const _FeatureList();

  /// Flagship features get a bolder treatment + an icon; the rest are listed
  /// plainly. Same 10 strings as before, just re-ordered for emphasis.
  static const _flagship = [
    (LucideIcons.award, 'Graduações por faixa & alunos ilimitados'),
    (LucideIcons.qrCode, 'Check-in por QR Code'),
    (LucideIcons.wallet, 'Financeiro & cobranças (Pix)'),
    (LucideIcons.smartphone, 'Portal do aluno (app)'),
  ];

  static const _rest = [
    'Turmas, horários e chamada',
    'Relatórios & retenção',
    'Loja virtual',
    'Campeonatos & ranking',
    'Multi-esporte',
    'Notificações push',
  ];

  @override
  Widget build(BuildContext context) {
    return PolishCard(
      radius: 16,
      color: AppTheme.surfaceVariant,
      border: Border.all(color: AppTheme.border),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tudo incluído em todos os planos',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          ..._flagship.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppTheme.successLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(f.$1, size: 15, color: AppTheme.success),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      f.$2,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1, color: AppTheme.border),
          const SizedBox(height: 12),
          Wrap(
            spacing: 0,
            runSpacing: 0,
            children: _rest.map((f) => _FeatureItem(label: f)).toList(),
          ),
        ],
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final String label;

  const _FeatureItem({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.check, size: 14, color: AppTheme.success),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trust signals
// ---------------------------------------------------------------------------

class _TrustRow extends StatelessWidget {
  const _TrustRow();

  @override
  Widget build(BuildContext context) {
    return PolishCard(
      radius: 14,
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        children: [
          Row(
            children: const [
              Expanded(
                child: _TrustChip(
                  icon: LucideIcons.xCircle,
                  label: 'Cancele\nquando quiser',
                ),
              ),
              _TrustDivider(),
              Expanded(
                child: _TrustChip(
                  icon: LucideIcons.shieldCheck,
                  label: 'Pagamento\nseguro',
                ),
              ),
              _TrustDivider(),
              Expanded(
                child: _TrustChip(
                  icon: LucideIcons.creditCard,
                  label: 'Pix, boleto\nou cartão',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Feito para academias de Jiu-Jitsu e artes marciais no Brasil.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrustChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppTheme.textPrimary),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _TrustDivider extends StatelessWidget {
  const _TrustDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: AppTheme.border,
    );
  }
}

// ---------------------------------------------------------------------------
// CTA Button
// ---------------------------------------------------------------------------

class _CtaButton extends StatelessWidget {
  final _PlanData plan;
  final bool loading;
  final VoidCallback onTap;

  const _CtaButton({
    required this.plan,
    required this.loading,
    required this.onTap,
  });

  String _fmt(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.textPrimary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.textDisabled,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'Assinar ${plan.label}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                          ),
                          TextSpan(
                            text: '  ·  R\$ ${_fmt(plan.monthlyEquivalent)}/mês',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.8),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(LucideIcons.arrowRight, size: 18),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

class _PlanData {
  final _BillingPlan key;
  final String label;
  final double price;
  final String period;
  final double monthlyEquivalent;
  final String? description;
  final int? savingsPct;
  final bool isPopular;

  const _PlanData({
    required this.key,
    required this.label,
    required this.price,
    required this.period,
    required this.monthlyEquivalent,
    required this.description,
    required this.savingsPct,
    required this.isPopular,
  });
}
