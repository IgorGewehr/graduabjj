import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../services/firebase_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/payment/subscription_detail_sheet.dart';

/// Tela admin de ASSINATURAS RECORRENTES (Mercado Pago Preapproval).
///
/// Por que existe: até aqui, o admin só conseguia parar uma assinatura
/// recorrente de aluno desconectando o Mercado Pago da academia inteira (o que
/// derrubava TODAS as cobranças). Esta tela lista as assinaturas ativas/pausadas
/// dos alunos e expõe as ações de cancelar / pausar / retomar por assinatura,
/// reutilizando o boundary já existente:
///   * dados: coleção `academies/{academyId}/subscriptions` (mesmo doc escrito
///     pelo backend — `createMpSubscription` + webhook), mapeado por
///     [Subscription.fromFirestore];
///   * ações: [SubscriptionDetailSheet], que chama os callables
///     cancel/pause/resume via [SubscriptionService] (o backend autoriza o admin
///     em `assertCanPayFor`). Os diálogos de confirmação — inclusive o aviso de
///     que cancelar é destrutivo e o aluno precisará reassinar — já vivem nesse
///     sheet, então não os reimplementamos aqui.
///
/// Premissas assumidas (documentadas):
///   * a coleção e o modelo são os mesmos do fluxo do aluno (confirmado em
///     [SubscriptionService]); apenas trocamos o filtro `studentId` por uma
///     consulta de toda a academia filtrada por status.
///   * "ativas/pausadas" = status em {authorized, pending, paused}. Concluídas
///     (`completed`), canceladas (`cancelled`) e falhas (`error`) ficam fora da
///     lista por padrão (não há o que gerenciar nelas).
class AdminSubscriptionsScreen extends ConsumerStatefulWidget {
  const AdminSubscriptionsScreen({super.key});

  @override
  ConsumerState<AdminSubscriptionsScreen> createState() =>
      _AdminSubscriptionsScreenState();
}

class _AdminSubscriptionsScreenState
    extends ConsumerState<AdminSubscriptionsScreen> {
  late final String _academyId;

  @override
  void initState() {
    super.initState();
    _academyId = FirebaseService.academyId;
  }

  /// Stream de todas as assinaturas gerenciáveis (ativas + pausadas) da academia.
  /// Lemos a coleção inteira e filtramos/ordenamos no cliente — a base de
  /// assinaturas recorrentes por academia é pequena (uma por aluno assinante),
  /// então não justifica índice composto; e assim reaproveitamos o mesmo
  /// [Subscription.fromFirestore] do fluxo do aluno sem divergir o modelo.
  Stream<List<Subscription>> _streamManageable() {
    return FirebaseService.firestore
        .collection('academies')
        .doc(_academyId)
        .collection('subscriptions')
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map(Subscription.fromFirestore)
          .where((s) =>
              s.status == 'authorized' ||
              s.status == 'pending' ||
              s.status == 'paused')
          .toList();
      // Pausadas primeiro (precisam de atenção do admin), depois ativas; dentro
      // de cada grupo, por nome do aluno para a lista ficar estável.
      int rank(Subscription s) => s.status == 'paused' ? 0 : 1;
      list.sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        return a.studentName
            .toLowerCase()
            .compareTo(b.studentName.toLowerCase());
      });
      return list;
    });
  }

  void _openDetail(Subscription sub) {
    // O sheet já traz cancelar/pausar/retomar/trocar-cartão com confirmação.
    // A stream desta tela atualiza sozinha quando o doc muda, então não
    // precisamos de onChanged.
    SubscriptionDetailSheet.show(
      context,
      sub: sub,
      academyId: _academyId,
      canManage: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Assinaturas'),
      ),
      body: StreamBuilder<List<Subscription>>(
        stream: _streamManageable(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorState(onRetry: () => setState(() {}));
          }
          final subs = snap.data ?? const <Subscription>[];
          if (subs.isEmpty) {
            return const _EmptyState();
          }

          final activeCount =
              subs.where((s) => s.status != 'paused').length;
          final pausedCount = subs.length - activeCount;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _SummaryHeader(
                activeCount: activeCount,
                pausedCount: pausedCount,
              ),
              const SizedBox(height: 16),
              for (final sub in subs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SubscriptionTile(
                    sub: sub,
                    onTap: () => _openDetail(sub),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Faixa de resumo no topo (quantas ativas / pausadas).
class _SummaryHeader extends StatelessWidget {
  final int activeCount;
  final int pausedCount;

  const _SummaryHeader({
    required this.activeCount,
    required this.pausedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            label: 'Ativas',
            value: activeCount.toString(),
            color: AppTheme.success,
            icon: LucideIcons.repeat,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryCard(
            label: 'Pausadas',
            value: pausedCount.toString(),
            color: AppTheme.warning,
            icon: LucideIcons.pause,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style:
                    AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                label,
                style: AppTheme.labelSmall
                    .copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Item de lista de uma assinatura: nome do aluno, valor mensal, status e
/// próxima cobrança (quando houver). Toque abre o sheet de gestão.
class _SubscriptionTile extends StatelessWidget {
  final Subscription sub;
  final VoidCallback onTap;

  const _SubscriptionTile({required this.sub, required this.onTap});

  ({String label, Color color}) get _statusChip {
    switch (sub.status) {
      case 'paused':
        return (label: 'Pausada', color: AppTheme.warning);
      default:
        // authorized / pending
        return (label: 'Ativa', color: AppTheme.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chip = _statusChip;
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final df = DateFormat('dd/MM/yyyy');

    final name = sub.studentName.trim().isEmpty
        ? 'Aluno sem nome'
        : sub.studentName.trim();

    // Subtítulo: próxima cobrança (se houver) ou prazo restante; dunning ganha
    // destaque para o admin saber que aquela assinatura está com cobrança
    // recusada (needsReauth).
    final subtitleParts = <String>[
      '${currency.format(sub.recurringValue)}/mês',
      if (sub.status != 'paused' && sub.nextBillingDate != null)
        'Próx.: ${df.format(sub.nextBillingDate!)}',
      if (sub.months > 0)
        '${sub.chargesPaid.clamp(0, sub.months)}/${sub.months} cobranças',
    ];

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(LucideIcons.repeat,
                    size: 20, color: AppTheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.titleSmall
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleParts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.textSecondary),
                    ),
                    if (sub.needsReauth) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(LucideIcons.alertTriangle,
                              size: 13, color: AppTheme.error),
                          const SizedBox(width: 4),
                          Text(
                            'Cobrança recusada',
                            style: AppTheme.labelSmall
                                .copyWith(color: AppTheme.error),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
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
                  const SizedBox(height: 8),
                  const Icon(LucideIcons.chevronRight,
                      size: 18, color: AppTheme.textSecondary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(LucideIcons.repeat,
                  size: 28, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhuma assinatura ativa',
              style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Quando um aluno assinar um plano recorrente no cartão, ele '
              'aparecerá aqui para você gerenciar (pausar ou cancelar).',
              textAlign: TextAlign.center,
              style:
                  AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.alertTriangle,
                size: 40, color: AppTheme.error),
            const SizedBox(height: 12),
            Text(
              'Não foi possível carregar as assinaturas',
              textAlign: TextAlign.center,
              style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
