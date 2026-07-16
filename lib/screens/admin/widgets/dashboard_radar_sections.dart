import '../../../services/fns.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/brand_tokens.dart';
import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../providers/portal_providers.dart';
import '../../../providers/retention_providers.dart';
import '../../../services/class_service.dart';

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

// ════════════════════════════════════════════════════════════════════════════
// 1. HOJE — aulas do dia + chamada 1-tap
// ════════════════════════════════════════════════════════════════════════════

class DashboardHojeCard extends ConsumerWidget {
  const DashboardHojeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classesAsync = ref.watch(classesProvider);
    // DateTime.weekday: seg=1..dom=7 → schedule usa 0=domingo..6=sábado.
    final todayDow = DateTime.now().weekday % 7;

    return _Section(
      title: 'Hoje',
      icon: LucideIcons.calendarClock,
      child: classesAsync.when(
        loading: () => _emptyLine('Carregando grade...'),
        error: (_, _) => _emptyLine('Grade indisponível.'),
        data: (classes) {
          // (turma, horário de hoje) ordenado por horário.
          final today = <(BJJClass, String)>[];
          for (final c in classes) {
            if (!c.isActive) continue;
            for (final s in c.schedule) {
              if (s.dayOfWeek == todayDow) today.add((c, s.startTime));
            }
          }
          today.sort((a, b) => a.$2.compareTo(b.$2));
          if (today.isEmpty) {
            return _emptyLine('Sem aulas na grade de hoje.');
          }
          return Column(
            children: [
              for (final (c, time) in today.take(5))
                _ClassRow(bjjClass: c, time: time),
              if (today.length > 5)
                _emptyLine('+ ${today.length - 5} aulas hoje'),
            ],
          );
        },
      ),
    );
  }
}

class _ClassRow extends StatelessWidget {
  const _ClassRow({required this.bjjClass, required this.time});
  final BJJClass bjjClass;
  final String time;

  @override
  Widget build(BuildContext context) {
    // Linha inteira tocável → Chamada. Sem botão por linha: o quick action
    // "Chamada" logo acima já é O CTA — repetir o rótulo 5x na mesma dobra
    // era ruído (feedback do dono).
    return InkWell(
      onTap: () => context.go('/admin/chamada'),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              child: Text(
                time,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  fontFeatures: Brand.tabular,
                  color: Brand.blood,
                ),
              ),
            ),
            Expanded(
              child: Text(
                bjjClass.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Icon(LucideIcons.chevronRight,
                size: 15, color: AppTheme.textDisabled),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 2. RADAR DE RETENÇÃO — quem está esfriando + taxa de recuperação
// ════════════════════════════════════════════════════════════════════════════

class DashboardRadarCard extends ConsumerWidget {
  const DashboardRadarCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(retentionStudentsProvider);
    final monthStats = ref.watch(retentionMonthStatsProvider).valueOrNull;

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
