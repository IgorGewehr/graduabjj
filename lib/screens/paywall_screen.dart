import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/academy.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/firebase_service.dart';

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
      final result = await FirebaseFunctions.instance
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

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
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
              )
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: -0.05, end: 0, duration: 400.ms, curve: Curves.easeOut),

              const SizedBox(height: 40),

              // Plan selector
              ..._plans.map((plan) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PlanCard(
                      plan: plan,
                      isSelected: _selected == plan.key,
                      // 1º mês com 50% off — só no Mensal e dentro da janela.
                      promoPrice: (promoEligible && plan.key == _BillingPlan.mensal)
                          ? plan.price / 2
                          : null,
                      onTap: () => setState(() => _selected = plan.key),
                    ).animate(delay: (100 * _plans.indexOf(plan)).ms)
                        .fadeIn(duration: 350.ms)
                        .slideY(begin: 0.04, end: 0, duration: 350.ms, curve: Curves.easeOut),
                  )),

              const SizedBox(height: 8),

              // Features list
              const _FeatureList()
                  .animate(delay: 350.ms)
                  .fadeIn(duration: 400.ms),

              const SizedBox(height: 32),

              // CTA button — assinatura recorrente (renova sozinha)
              _CtaButton(
                plan: _plans.firstWhere((p) => p.key == _selected),
                loading: _launching,
                onTap: () => _openCheckout(recurring: true),
              ).animate(delay: 400.ms)
                  .fadeIn(duration: 350.ms)
                  .slideY(begin: 0.04, end: 0, duration: 350.ms, curve: Curves.easeOut),

              const SizedBox(height: 12),

              // Pagamento avulso — Pix/boleto/cartão à vista (não renova)
              TextButton(
                onPressed:
                    _launching ? null : () => _openCheckout(recurring: false),
                child: const Text(
                  'Pagar à vista (Pix ou boleto)',
                  style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                ),
              ).animate(delay: 430.ms).fadeIn(duration: 300.ms),

              const SizedBox(height: 16),

              // WhatsApp support
              TextButton.icon(
                onPressed: _openWhatsApp,
                icon: const Icon(LucideIcons.messageCircle, size: 16),
                label: const Text('Falar com suporte'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  textStyle: const TextStyle(fontSize: 14),
                ),
              ).animate(delay: 450.ms).fadeIn(duration: 300.ms),

              const SizedBox(height: 8),

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
                        style:
                            TextStyle(fontSize: 13, color: AppTheme.textDisabled),
                      ),
              ).animate(delay: 500.ms).fadeIn(duration: 300.ms),

              const SizedBox(height: 32),
            ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Logo
        Image.asset(
          'assets/images/bjjeasy_logo.png',
          height: 72,
        ),
        const SizedBox(height: 24),

        Text(
          pastDue
              ? 'Pagamento não confirmado'
              : isTrialing
                  ? daysLeft <= 3
                      ? 'Seu trial encerra em $daysLeft dia${daysLeft != 1 ? 's' : ''}'
                      : 'Escolha seu plano'
                  : 'Período de avaliação encerrado',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
            letterSpacing: -0.5,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),

        Text(
          pastDue
              ? 'Não conseguimos renovar sua assinatura. Atualize seu pagamento para continuar usando o BJJEasy.'
              : isTrialing
                  ? 'Assine agora e continue gerenciando sua academia sem interrupções.'
                  : 'Assine para continuar usando todos os recursos do BJJEasy.',
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.textPrimary : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.textPrimary : AppTheme.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            // Selection indicator
            AnimatedContainer(
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
            ),
            const SizedBox(width: 14),

            // Plan info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        plan.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : AppTheme.textPrimary,
                        ),
                      ),
                      if (plan.isPopular) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.2)
                                : AppTheme.textPrimary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Mais popular',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                      if (promoPrice != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.2)
                                : AppTheme.success,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            '-50% 1º mês',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (plan.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      plan.description!,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.7)
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Price + savings
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (plan.savingsPct != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.15)
                          : AppTheme.successLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${plan.savingsPct}% off',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : AppTheme.success,
                      ),
                    ),
                  ),
                if (promoPrice != null) ...[
                  Text(
                    'R\$ ${_fmt(plan.price)}',
                    style: TextStyle(
                      fontSize: 12,
                      decoration: TextDecoration.lineThrough,
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.6)
                          : AppTheme.textSecondary,
                    ),
                  ),
                  Text(
                    'R\$ ${_fmt(promoPrice!)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? Colors.white : AppTheme.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    '1º mês',
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.7)
                          : AppTheme.textSecondary,
                    ),
                  ),
                ] else ...[
                  Text(
                    'R\$ ${_fmt(plan.price)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? Colors.white : AppTheme.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    '/${plan.period}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.7)
                          : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
}

// ---------------------------------------------------------------------------
// Feature list
// ---------------------------------------------------------------------------

class _FeatureList extends StatelessWidget {
  const _FeatureList();

  static const _features = [
    'Alunos & graduações ilimitados',
    'Check-in por QR Code',
    'Turmas, horários e chamada',
    'Financeiro & cobranças',
    'Portal do aluno (app)',
    'Relatórios & retenção',
    'Loja virtual',
    'Campeonatos',
    'Multi-esporte',
    'Notificações push',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tudo incluído em todos os planos',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 0,
            runSpacing: 0,
            children: _features
                .map((f) => _FeatureItem(label: f))
                .toList(),
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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
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
                  Text(
                    'Assinar plano ${plan.label}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
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
