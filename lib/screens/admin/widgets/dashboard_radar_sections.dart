import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/brand_tokens.dart';
import '../../../core/theme.dart';
import '../../../models/feed_post.dart';
import '../../../models/student.dart';
import '../../../providers/friend_providers.dart';
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
      onSeeAll: () => context.go('/admin/chamada'),
      seeAllLabel: 'Chamada',
      child: classesAsync.when(
        loading: () => _emptyLine('Carregando grade...'),
        error: (_, _) => _emptyLine('Grade indisponível.'),
        data: (classes) {
          // (turma, horário de hoje) ordenado por horário.
          final today = <(BJJClass, String)>[];
          for (final c in classes) {
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            time,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              fontFeatures: Brand.tabular,
              color: Brand.ink,
            ),
          ),
          const SizedBox(width: 12),
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
          // Chamada 1-tap — a ação nº 1 do professor a 1 toque do login.
          GestureDetector(
            onTap: () => context.go('/admin/chamada'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Brand.ink,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'CHAMADA',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
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
          // Esfriando = risco high/critical (job diário) OU, antes do score
          // existir, fallback: ativo há 14+ dias sem treinar.
          final risky = students.where((s) {
            final level = s.retention?.riskLevel;
            if (level == 'high' || level == 'critical') return true;
            if (level == null) return (s.daysSinceLastAttendance ?? 0) >= 14;
            return false;
          }).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (risky.isEmpty)
                _emptyLine('Ninguém esfriando — tatame saudável. 👊')
              else ...[
                Text(
                  '${risky.length} aluno${risky.length == 1 ? '' : 's'} esfriando',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Brand.blood,
                  ),
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
// 3. ENGAJAMENTO — o termômetro B2C que não existia
// ════════════════════════════════════════════════════════════════════════════

class DashboardEngajamentoCard extends ConsumerWidget {
  const DashboardEngajamentoCard({super.key});

  /// Streak semanal a partir dos buckets persistidos: semanas consecutivas com
  /// treino terminando na semana corrente (com grace: semana corrente vazia
  /// não quebra — mesmo contrato do streak do aluno).
  static int _streakFromBuckets(List<int> buckets) {
    if (buckets.isEmpty) return 0;
    var i = buckets.length - 1;
    if (buckets[i] == 0) i--; // grace da semana corrente
    var streak = 0;
    while (i >= 0 && buckets[i] > 0) {
      streak++;
      i--;
    }
    return streak;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(retentionStudentsProvider);
    final feedAsync = ref.watch(staffAcademyFeedProvider);

    return _Section(
      title: 'Engajamento',
      icon: LucideIcons.flame,
      onSeeAll: () => context.go('/admin/social'),
      seeAllLabel: 'Social',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          studentsAsync.when(
            loading: () => _emptyLine('...'),
            error: (_, _) => const SizedBox.shrink(),
            data: (students) {
              final now = DateTime.now();
              var onStreak = 0;
              var trainedThisWeek = 0;
              for (final s in students) {
                final buckets = s.last8WeeksBuckets(now);
                if (_streakFromBuckets(buckets) >= 4) onStreak++;
                if (buckets.isNotEmpty && buckets.last > 0) trainedThisWeek++;
              }
              return Row(
                children: [
                  _Stat(value: '$onStreak', label: 'STREAKS 4+ SEM'),
                  const SizedBox(width: 20),
                  _Stat(value: '$trainedThisWeek', label: 'TREINARAM NA SEMANA'),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          feedAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (posts) {
              final cutoff = DateTime.now().subtract(const Duration(days: 7));
              final week = posts
                  .where((p) =>
                      !p.hiddenByStaff && p.occurredAt.isAfter(cutoff))
                  .toList();
              // Marcos que valem reconhecer NA AULA — ponte app → tatame
              // (custo zero, muito BJJ): graduação, streak e marco de tatame.
              final marcos = week
                  .where((p) =>
                      p.type == FeedPostType.graduacao ||
                      p.type == FeedPostType.streakMilestone ||
                      p.type == FeedPostType.matMilestone)
                  .take(3)
                  .toList();
              final likes =
                  week.fold<int>(0, (sum, p) => sum + p.likeCount);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${week.length} marco${week.length == 1 ? '' : 's'} no feed '
                    'essa semana · $likes salve${likes == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  if (marcos.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'PARA RECONHECER NA AULA',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                        color: Brand.ash,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final p in marcos)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.award,
                                size: 13, color: Brand.blood),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${p.authorName} — ${p.displayHeadline}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            fontFeatures: Brand.tabular,
            color: Brand.ink,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        const SizedBox(height: 0),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: Brand.ash,
          ),
        ),
      ],
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
    await FirebaseFunctions.instance
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
