import '../../../services/fns.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/brand_tokens.dart';
import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../providers/join_request_providers.dart';
import '../../../providers/retention_providers.dart';

/// Seções B2C do dashboard "Radar do dia" (REPAGINADA §6):
/// HOJE (aulas do dia + chamada 1-tap) · RADAR (alunos esfriando) ·
/// ENGAJAMENTO (streaks, feed, marcos para reconhecer na aula).
/// Todas leem dados persistidos/baratos — zero query pesada no client.

// ════════════════════════════════════════════════════════════════════════════
// Moldura comum das seções
// ════════════════════════════════════════════════════════════════════════════

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
    this.onSeeAll,
    this.seeAllLabel,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final VoidCallback? onSeeAll;
  final String? seeAllLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
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
                Icon(icon, size: 16, color: Brand.blood),
                const SizedBox(width: 8),
                // Header em voz fighter (§5.2): uppercase, w900, tracking.
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: Brand.ink,
                  ),
                ),
                const Spacer(),
                if (onSeeAll != null)
                  GestureDetector(
                    onTap: onSeeAll,
                    child: Text(
                      seeAllLabel ?? 'Ver tudo',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Brand.blood,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

Widget _emptyLine(String msg) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        msg,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
        ),
      ),
    );

// Card HOJE removido por decisão do dono (21/07): o professor conhece a
// própria grade — o card era redundante no dashboard. A chamada 1-tap
// permanece nas ações rápidas do dashboard e na aba Chamada.



// ════════════════════════════════════════════════════════════════════════════
// 2. RADAR DE RETENÇÃO — quem está esfriando + taxa de recuperação
// ════════════════════════════════════════════════════════════════════════════

class DashboardRadarCard extends ConsumerWidget {
  const DashboardRadarCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(retentionStudentsProvider);
    final monthStats = ref.watch(retentionMonthStatsProvider).valueOrNull;
    // Fila de solicitações de entrada pendentes (spec 2.3 — hoje só há um
    // badge dentro de Alunos; isso dá um 2º ponto de descoberta no dashboard
    // sem duplicar o badge existente).
    final pendingRequests = ref.watch(pendingJoinRequestsCountProvider);

    return Column(
      children: [
        if (pendingRequests > 0) ...[
          _Section(
            title: 'Solicitações',
            icon: LucideIcons.userPlus,
            onSeeAll: () => context.push('/admin/alunos/solicitacoes'),
            seeAllLabel: 'Ver',
            child: GestureDetector(
              onTap: () => context.push('/admin/alunos/solicitacoes'),
              child: Text(
                pendingRequests == 1
                    ? '1 solicitação de aluno aguardando'
                    : '$pendingRequests solicitações de alunos aguardando',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Brand.ink,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _buildRetentionSection(context, studentsAsync, monthStats),
      ],
    );
  }

  Widget _buildRetentionSection(
    BuildContext context,
    AsyncValue<List<Student>> studentsAsync,
    RetentionMonthStats? monthStats,
  ) {
    return _Section(
      title: 'Radar de retenção',
      icon: LucideIcons.heartPulse,
      onSeeAll: () => context.go('/admin/retencao'),
      seeAllLabel: 'Retenção',
      child: studentsAsync.when(
        loading: () => _emptyLine('Escaneando...'),
        error: (_, _) => _emptyLine('Radar indisponível.'),
        data: (students) {
          // REGRA DO RADAR: só quem TAVA treinando e está esfriando —
          // mesma régua da tela de Retenção (isCoolingAthlete). Nunca-treinou
          // é problema de ativação e não entra aqui.
          final risky = students.where(isCoolingAthlete).toList();

          // Esfriou HÁ MENOS TEMPO primeiro: pegar o aluno com 7 dias de
          // sumiço é muito mais recuperável do que o de 37 — o dashboard
          // mostra os mais frescos; a lista completa fica na Retenção.
          risky.sort((a, b) => (a.daysSinceLastAttendance ?? 999)
              .compareTo(b.daysSinceLastAttendance ?? 999));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (risky.isEmpty)
                _emptyLine('Ninguém esfriando — tatame saudável. 👊')
              else ...[
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: '${risky.length} ',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        fontFeatures: Brand.tabular,
                        color: Brand.blood,
                      ),
                    ),
                    TextSpan(
                      text:
                          'esfriando · os mais recentes primeiro',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                for (final s in risky.take(4)) _RiskRow(student: s),
              ],
              if (monthStats != null && monthStats.contacted > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'De ${monthStats.contacted} contatados este mês, '
                  '${monthStats.recovered} voltaram.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RiskRow extends StatelessWidget {
  const _RiskRow({required this.student});
  final Student student;

  @override
  Widget build(BuildContext context) {
    final days = student.daysSinceLastAttendance;
    final critical = student.retention?.riskLevel == 'critical';
    final phoneDigits =
        (student.phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: critical ? Brand.blood : AppTheme.warning,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => context.go('/admin/retencao'),
              child: Text(
                student.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
          Text(
            days != null ? '${days}d sem treinar' : 'nunca treinou',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: Brand.tabular,
              color: AppTheme.textSecondary,
            ),
          ),
          if (phoneDigits.length >= 10) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                final first = student.fullName.split(' ').first;
                final msg = Uri.encodeComponent(
                  'Fala $first! Sentimos sua falta no tatame. '
                  'Bora treinar essa semana? 👊',
                );
                final wa = phoneDigits.length <= 11
                    ? '55$phoneDigits'
                    : phoneDigits;
                launchUrl(
                  Uri.parse('https://wa.me/$wa?text=$msg'),
                  mode: LaunchMode.externalApplication,
                );
              },
              child: const Icon(
                LucideIcons.messageCircle,
                size: 18,
                color: Color(0xFF25D366),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Broadcast "Avisar todos" (§4) — UI para a callable sendAcademyNotification
// ════════════════════════════════════════════════════════════════════════════

/// Dialog de aviso push para TODOS os alunos da academia (canal 'academy',
/// respeitando o opt-out do aluno). Só o ADMIN consegue (a callable valida
/// adminUserId server-side).
Future<void> showBroadcastDialog(BuildContext context, String academyId) async {
  final titleCtrl = TextEditingController();
  final bodyCtrl = TextEditingController();
  final sent = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Avisar todos',
          style: TextStyle(fontWeight: FontWeight.w900)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: titleCtrl,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Título',
              hintText: 'Ex.: Mutirão de graduação sábado',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: bodyCtrl,
            maxLength: 160,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Mensagem',
              hintText: 'Aviso curto para todos os alunos com o app',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('CANCELAR',
              style: TextStyle(color: Brand.ash, fontWeight: FontWeight.w800)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Brand.blood),
          onPressed: () {
            if (titleCtrl.text.trim().isEmpty ||
                bodyCtrl.text.trim().isEmpty) {
              return;
            }
            Navigator.pop(ctx, true);
          },
          child: const Text('ENVIAR',
              style: TextStyle(fontWeight: FontWeight.w900)),
        ),
      ],
    ),
  );

  if (sent != true) return;
  try {
    await Fns.functions
        .httpsCallable('sendAcademyNotification')
        .call<Map<String, dynamic>>({
      'academyId': academyId,
      'title': titleCtrl.text.trim(),
      'body': bodyCtrl.text.trim(),
      'notificationData': {'category': 'academy'},
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aviso enviado para a academia.'),
        backgroundColor: Brand.ink,
      ));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Não deu para enviar o aviso.'),
        backgroundColor: Brand.blood,
      ));
    }
  }
}
