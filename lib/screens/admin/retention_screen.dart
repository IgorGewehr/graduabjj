import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/brand_tokens.dart';
import '../../core/constants.dart';
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../providers/portal_providers.dart';
import '../../providers/retention_providers.dart';
import '../../services/firebase_service.dart';
import '../../services/retention_contact_service.dart';
import '../../services/student_service.dart';
import '../../widgets/polish/polish.dart';
import 'widgets/technical_goal_dialog.dart';

/// Retenção 2.0 — RADAR ACIONÁVEL (§3.1/§3.2 do plano Repaginada).
///
/// Lê os campos persistidos `retention.*` (CF onAttendanceWrite + job diário)
/// — abre instantânea, ZERO varredura de payments/attendance no client.
/// Cada aluno em risco ganha 3 ações reais: WhatsApp 1-tap, push in-app e
/// registro de contato manual. O job diário fecha o loop (pending → recovered)
/// e alimenta a métrica "De N contatados este mês, M voltaram".
///
/// Privacidade: risco e histórico de contato são dado INTERNO da academia —
/// nunca visíveis ao aluno (LGPD / não estigmatizar).
class AdminRetentionScreen extends ConsumerWidget {
  const AdminRetentionScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    ref.invalidate(retentionStudentsProvider);
    ref.invalidate(retentionMonthStatsProvider);
    ref.invalidate(retentionPendingContactIdsProvider);
    ref.invalidate(latestSnapshotProvider);
    await ref.read(retentionStudentsProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(retentionStudentsProvider);

    return Scaffold(
      backgroundColor: Brand.bone,
      appBar: AppBar(title: const Text('Retenção')),
      body: RefreshIndicator(
        color: Brand.blood,
        onRefresh: () => _refresh(ref),
        child: studentsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 140),
              Center(
                child: Text(
                  'Não deu pra carregar o radar.\nPuxe para atualizar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Brand.ash, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          data: (students) => _Body(students: students),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Corpo — header + banner + lista acionável
// ════════════════════════════════════════════════════════════════════════════

class _Body extends ConsumerWidget {
  const _Body({required this.students});

  /// Alunos ATIVOS já ordenados por risco pelo provider.
  final List<Student> students;

  bool _isAtRisk(Student s) {
    // REGRA DO RADAR: só quem TAVA treinando e está esfriando
    // ([isCoolingAthlete]) — nunca-treinou/2-aulas-na-vida é problema de
    // ATIVAÇÃO e fica fora (antes o score v1 marcava todos como crítico e o
    // radar nascia poluído). bluesRisk (§6.3) segue como qualificador: o
    // detector da CF já exige histórico real (promoção registrada p/ azul).
    return isCoolingAthlete(s) || s.retention?.bluesRisk == true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Job diário já rodou para pelo menos um aluno? Senão, modo fallback:
    // banner + agrupamento por dias de inatividade.
    final radarReady = students.any((s) => s.retention?.riskScore != null);
    final atRisk = students.where(_isAtRisk).toList();

    // Contagens do header.
    final int cCritical;
    final int cHigh;
    final int cMedium;
    if (radarReady) {
      // Contagens sobre o UNIVERSO DO RADAR (atRisk), não a academia inteira —
      // senão alunos nunca-engataram (score alto por inatividade) inflavam o
      // header com "N críticos" que não estão na lista.
      cCritical =
          atRisk.where((s) => s.retention?.riskLevel == 'critical').length;
      cHigh = atRisk.where((s) => s.retention?.riskLevel == 'high').length;
      cMedium = atRisk.where((s) => s.retention?.riskLevel == 'medium').length;
    } else {
      int band(Student s, bool Function(int) test) {
        final d = s.daysSinceLastAttendance;
        return d != null && test(d) ? 1 : 0;
      }

      cCritical = students.fold(0, (acc, s) => acc + band(s, (d) => d > 30));
      cHigh = students.fold(0, (acc, s) => acc + band(s, (d) => d >= 15 && d <= 30));
      cMedium = students.fold(0, (acc, s) => acc + band(s, (d) => d >= 7 && d < 15));
    }

    final children = <Widget>[
      _Header(
        critical: cCritical,
        high: cHigh,
        medium: cMedium,
        radarReady: radarReady,
      ).fadeInQuick(),
      if (!radarReady) const _PreparingBanner(),
      const SizedBox(height: 4),
    ];

    if (atRisk.isEmpty) {
      children.addAll(const [
        SizedBox(height: 60),
        PolishedEmptyState(
          icon: LucideIcons.shieldCheck,
          accent: AppTheme.success,
          title: 'Ninguém esfriando',
          subtitle: 'Todos os alunos ativos treinaram\nnos últimos 7 dias.',
        ),
      ]);
    } else if (radarReady) {
      for (var i = 0; i < atRisk.length; i++) {
        children.add(_RetentionCard(student: atRisk[i]).entrance(index: i));
      }
    } else {
      // Fallback: agrupa por banda de inatividade (30+/15–30/7–14).
      final b30 = atRisk
          .where((s) => (s.daysSinceLastAttendance ?? 0) > 30)
          .toList();
      final b15 = atRisk.where((s) {
        final d = s.daysSinceLastAttendance ?? 0;
        return d >= 15 && d <= 30;
      }).toList();
      final b7 = atRisk.where((s) {
        final d = s.daysSinceLastAttendance ?? 0;
        return d >= 7 && d < 15;
      }).toList();

      void section(String label, Color color, List<Student> list) {
        if (list.isEmpty) return;
        children.add(_SectionHeader(label: label, color: color, count: list.length));
        children.addAll(list.map((s) => _RetentionCard(student: s)));
      }

      section('30+ DIAS SEM TREINAR', Brand.blood, b30);
      section('15–30 DIAS', _kHighColor, b15);
      section('7–14 DIAS', _kMediumColor, b7);
    }

    children.add(const SizedBox(height: 32));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      children: children,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Header — contagem por nível + métrica de recuperação do mês
// ════════════════════════════════════════════════════════════════════════════

class _Header extends ConsumerWidget {
  const _Header({
    required this.critical,
    required this.high,
    required this.medium,
    required this.radarReady,
  });

  final int critical;
  final int high;
  final int medium;
  final bool radarReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(retentionMonthStatsProvider).valueOrNull ??
        RetentionMonthStats.zero;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Brand.ash.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RADAR DE RETENÇÃO',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
              color: Brand.ash.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _LevelStat(
                count: critical,
                label: radarReady ? 'CRÍTICO' : '30+ DIAS',
                color: Brand.blood,
              ),
              _LevelStat(
                count: high,
                label: radarReady ? 'ALTO' : '15–30 DIAS',
                color: _kHighColor,
              ),
              _LevelStat(
                count: medium,
                label: radarReady ? 'MÉDIO' : '7–14 DIAS',
                color: _kMediumColor,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: Brand.ash.withValues(alpha: 0.15)),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(LucideIcons.heartHandshake, size: 16, color: Brand.ink),
              const SizedBox(width: 8),
              Expanded(
                child: stats.contacted == 0
                    ? const Text(
                        'Nenhum contato registrado este mês.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Brand.ash,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Brand.ink,
                            fontWeight: FontWeight.w600,
                            fontFeatures: Brand.tabular,
                          ),
                          children: [
                            const TextSpan(text: 'De '),
                            TextSpan(
                              text: '${stats.contacted}',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const TextSpan(text: ' contatados este mês, '),
                            TextSpan(
                              text: '${stats.recovered}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: AppTheme.success,
                              ),
                            ),
                            TextSpan(
                              text: stats.recovered == 1
                                  ? ' voltou ao treino.'
                                  : ' voltaram ao treino.',
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LevelStat extends StatelessWidget {
  const _LevelStat({
    required this.count,
    required this.label,
    required this.color,
  });

  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1.0,
              color: count > 0 ? color : Brand.ash.withValues(alpha: 0.5),
              fontFeatures: Brand.tabular,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Brand.ash,
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner discreto do modo fallback (job diário ainda não rodou).
class _PreparingBanner extends StatelessWidget {
  const _PreparingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _kMediumColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kMediumColor.withValues(alpha: 0.25)),
      ),
      child: const Row(
        children: [
          Icon(LucideIcons.radar, size: 16, color: _kMediumColor),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Radar em preparação — dados completos após o próximo ciclo diário.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Brand.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.color,
    required this.count,
  });

  final String label;
  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
              color: Brand.ink,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Brand.ash.withValues(alpha: 0.9),
              fontFeatures: Brand.tabular,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Card acionável por aluno em risco
// ════════════════════════════════════════════════════════════════════════════

class _RetentionCard extends ConsumerStatefulWidget {
  const _RetentionCard({required this.student});

  final Student student;

  @override
  ConsumerState<_RetentionCard> createState() => _RetentionCardState();
}

class _RetentionCardState extends ConsumerState<_RetentionCard> {
  bool _expanded = false;
  bool _busy = false;

  Student get student => widget.student;

  /// Nível efetivo para o badge: riskLevel do job quando existe; senão a banda
  /// de inatividade (fallback pré-primeiro-ciclo).
  String? get _effectiveLevel {
    final lvl = student.retention?.riskLevel;
    if (lvl != null) return lvl;
    final d = student.daysSinceLastAttendance;
    if (d == null) return null;
    if (d > 30) return 'critical';
    if (d >= 15) return 'high';
    if (d >= 7) return 'medium';
    return null;
  }

  /// Flag anti-"blue belt blues" (§6.3) computada pela CF diária: faixa-azul
  /// esfriando. Qualifica o aluno na lista (chip + playbook próprio) — o tom
  /// do reengajamento muda de "sentimos sua falta" para reconhecimento +
  /// desafio técnico.
  bool get _isBlues => student.retention?.bluesRisk == true;

  String? get _waPhone {
    final raw = student.phone;
    if (raw == null) return null;
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    digits = digits.replaceFirst(RegExp(r'^0+'), '');
    if (digits.length < 10) return null;
    // DDI 55 só quando ainda não presente (12+ dígitos já incluem o DDI;
    // 10–11 dígitos começando com 55 são DDD 55 — região de Santa Maria).
    if (!(digits.length >= 12 && digits.startsWith('55'))) {
      digits = '55$digits';
    }
    return digits;
  }

  String get _firstName {
    final parts = student.fullName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? 'atleta' : parts.first;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Registro (comum às 3 ações)
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _register({
    required String channel,
    String? templateId,
    String? note,
    String successMessage = 'Contato registrado',
  }) async {
    try {
      await ref.read(retentionContactServiceProvider).registerContact(
            studentId: student.id,
            channel: channel,
            templateId: templateId,
            note: note,
          );
      ref.invalidate(studentRetentionContactsProvider(student.id));
      ref.invalidate(retentionMonthStatsProvider);
      ref.invalidate(retentionPendingContactIdsProvider);
      if (mounted) context.showSuccess(successMessage);
    } catch (_) {
      if (mounted) context.showError('Não deu pra registrar o contato');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Ação (a): WhatsApp 1-tap
  // ──────────────────────────────────────────────────────────────────────────

  _WaTemplate get _waTemplate {
    // Blues (§6.3 arma 1): reconhecimento + desafio técnico. NUNCA mencionar
    // que o aluno sumiu — cobrança de presença é exatamente o que afunda um
    // faixa-azul em estagnação.
    if (_isBlues) {
      return _WaTemplate(
        'retention_blues_challenge',
        (name, academy) =>
            'Fala $name! Teu jogo tá evoluindo demais — dá pra ver no tatame. '
            'Semana que vem quero te passar uma meta técnica nova, tem uma '
            'chave que é a tua cara. Bora? 👊',
      );
    }
    final d = student.daysSinceLastAttendance ?? 999;
    if (d > 30) {
      return _WaTemplate(
        'retention_30d_plus',
        (name, academy) =>
            'Oi $name! Aqui é o professor da $academy. Seu professor quer te '
            'ver de volta no tatame! Se algo tá dificultando o retorno, me '
            'chama que a gente resolve juntos. Te espero no treino 👊',
      );
    }
    if (d >= 15) {
      return _WaTemplate(
        'retention_15_30d',
        (name, academy) =>
            'E aí $name, tudo certo? Aqui é o professor da $academy. Já faz '
            'um tempinho que você não aparece... bora voltar pro tatame? '
            'A equipe sente sua falta 🥋',
      );
    }
    return _WaTemplate(
      'retention_7_14d',
      (name, academy) =>
          'Oi $name! Aqui é o professor da $academy. Sentimos sua falta no '
          'treino essa semana — o tatame não é o mesmo sem você. Bora treinar? 👊',
    );
  }

  Future<void> _onWhatsApp() async {
    final phone = _waPhone;
    if (phone == null || _busy) return;
    setState(() => _busy = true);
    try {
      // ANTI-ASSÉDIO: WhatsApp máx. 1/14 dias por aluno — se já houve contato
      // recente, exige confirmação extra explícita.
      List<RetentionContact> history = const [];
      try {
        history = await ref
            .read(retentionContactServiceProvider)
            .listForStudent(student.id, limit: 20);
      } catch (_) {}
      if (!mounted) return;

      RetentionContact? recentWa;
      for (final c in history) {
        if (c.channel == 'whatsapp' &&
            c.at != null &&
            DateTime.now().difference(c.at!).inDays <= 14) {
          recentWa = c;
          break;
        }
      }
      if (recentWa != null) {
        final daysAgo = DateTime.now().difference(recentWa.at!).inDays;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            title: Text(
              daysAgo == 0 ? 'Contatado hoje' : 'Contatado há $daysAgo dias',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            content: Text(
              '$_firstName já recebeu um WhatsApp de reengajamento '
              '${daysAgo == 0 ? 'hoje' : 'há $daysAgo dia${daysAgo == 1 ? '' : 's'}'}. '
              'Mandar de novo tão cedo pode soar como cobrança. Enviar mesmo assim?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'AGORA NÃO',
                  style: TextStyle(color: Brand.ash, fontWeight: FontWeight.w800),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Brand.blood),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'ENVIAR MESMO ASSIM',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        );
        if (proceed != true || !mounted) return;
      }

      final template = _waTemplate;
      final academy =
          ref.read(academyNameProvider).valueOrNull ?? 'nossa academia';
      final text = await _showMessageSheet(
        initial: template.build(_firstName, academy),
      );
      if (text == null || text.trim().isEmpty || !mounted) return;

      final uri = Uri.parse(
        'https://wa.me/$phone?text=${Uri.encodeComponent(text.trim())}',
      );
      bool launched = false;
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
      if (!mounted) return;
      if (!launched) {
        context.showWarning('Não deu pra abrir o WhatsApp neste aparelho');
        return;
      }

      // Ao voltar do launch: registrar o contato?
      final register = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Registrar esse contato?',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: const Text(
            'O contato entra no histórico do aluno e o radar mede sozinho se '
            'ele voltou a treinar em até 14 dias.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'AGORA NÃO',
                style: TextStyle(color: Brand.ash, fontWeight: FontWeight.w800),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Brand.ink),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'REGISTRAR',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      );
      if (register == true && mounted) {
        await _register(channel: 'whatsapp', templateId: template.id);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sheet com a mensagem EDITÁVEL + botão "Abrir WhatsApp".
  Future<String?> _showMessageSheet({required String initial}) {
    final controller = TextEditingController(text: initial);
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'MENSAGEM DE REENGAJAMENTO',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: Brand.ink,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Edite à vontade — vai na sua voz, não na do app.',
              style: TextStyle(fontSize: 12, color: Brand.ash),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              maxLines: 6,
              minLines: 4,
              style: const TextStyle(fontSize: 14, height: 1.4),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Brand.blood,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => Navigator.pop(ctx, controller.text),
              icon: const Icon(LucideIcons.messageCircle, size: 18),
              label: const Text(
                'ABRIR WHATSAPP',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Ação (b): push in-app (só aluno com conta vinculada)
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _onPush() async {
    final targetUid = student.linkedUserId;
    if (targetUid == null || _busy) return;

    final titleCtrl =
        TextEditingController(text: 'Seu professor mandou um salve 👊');
    final bodyCtrl = TextEditingController(
      text: 'Sentimos sua falta no tatame. Bora treinar essa semana?',
    );
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          'Push para $_firstName',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Título',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bodyCtrl,
              maxLines: 3,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: 'Mensagem',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'CANCELAR',
              style: TextStyle(color: Brand.ash, fontWeight: FontWeight.w800),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.blood),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'ENVIAR',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    if (send != true || !mounted) return;

    final title = titleCtrl.text.trim();
    final body = bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      context.showWarning('Título e mensagem são obrigatórios');
      return;
    }

    setState(() => _busy = true);
    try {
      // Assinatura real da callable (server_functions.js):
      // { targetUserId, title, body, academyId, notificationData? }.
      await FirebaseFunctions.instance
          .httpsCallable('sendUserNotification')
          .call<dynamic>({
        'targetUserId': targetUid,
        'title': title,
        'body': body,
        'academyId': FirebaseService.academyId,
        'notificationData': {'type': 'retention_reengagement'},
      });
      if (!mounted) return;
      await _register(
        channel: 'push',
        templateId: 'retention_push_salve',
        successMessage: 'Push enviado e contato registrado',
      );
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        context.showError(
          e.code == 'permission-denied'
              ? 'Só o dono da academia pode enviar push'
              : 'Não deu pra enviar o push',
        );
      }
    } catch (_) {
      if (mounted) context.showError('Não deu pra enviar o push');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Ação (c): registrar contato manual (telefone / pessoalmente)
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _onManualContact() async {
    if (_busy) return;
    final noteCtrl = TextEditingController();
    var channel = 'phone';

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'REGISTRAR CONTATO',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: Brand.ink,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('TELEFONE'),
                      labelStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: channel == 'phone' ? Colors.white : Brand.ink,
                      ),
                      selected: channel == 'phone',
                      selectedColor: Brand.ink,
                      onSelected: (_) => setSheetState(() => channel = 'phone'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('PESSOALMENTE'),
                      labelStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: channel == 'inperson' ? Colors.white : Brand.ink,
                      ),
                      selected: channel == 'inperson',
                      selectedColor: Brand.ink,
                      onSelected: (_) =>
                          setSheetState(() => channel = 'inperson'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                maxLength: 300,
                decoration: InputDecoration(
                  labelText: 'Nota (opcional)',
                  hintText: 'Ex.: falou que volta semana que vem',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.ink,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'REGISTRAR',
                  style:
                      TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true && mounted) {
      await _register(channel: channel, note: noteCtrl.text);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Playbook blues (§6.3 arma 1): meta técnica — MESMO dialog da ficha
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _onDefineGoal() async {
    if (_busy) return;
    final staff = ref.read(currentUserProvider).valueOrNull;
    final result = await showTechnicalGoalDialog(
      context,
      studentId: student.id,
      studentName: student.fullName,
      current: student.activeGoal,
      staffName: staff?.displayName ?? 'Professor',
    );
    // Recarrega a lista para o playbook refletir a meta recém-salva/concluída.
    if (result != null) ref.invalidate(retentionStudentsProvider);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Sugerir inativar (§2.3) — SEMPRE decisão humana com confirmação
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _onSuggestInactivate() async {
    if (_busy) return;
    final days = student.daysSinceLastAttendance ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Marcar como inativo?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          '${student.fullName} está há $days dias sem treinar e sem contato '
          'em aberto. Marcar como inativo tira o aluno do radar e das '
          'cobranças recorrentes. Nada é automático — a decisão é sua e dá '
          'pra reverter na ficha do aluno.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'CANCELAR',
              style: TextStyle(color: Brand.ash, fontWeight: FontWeight.w800),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.blood),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'INATIVAR',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await StudentService(FirebaseService.academyId).updateStatus(
        student.id,
        StudentStatus.inactive,
        reason: 'suggested_inactive',
      );
      ref.invalidate(retentionStudentsProvider);
      if (mounted) context.showSuccess('$_firstName marcado como inativo');
    } catch (_) {
      if (mounted) context.showError('Não deu pra atualizar o status');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Playbook blues (expandido) — DIFERENTE do inadimplente/sumido (§6.3):
  // reconhecimento + desafio técnico, nunca cobrança de presença.
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildBluesPlaybook() {
    final goal = student.activeGoal;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 2),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.beltBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.beltBlue.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(LucideIcons.compass, size: 13, color: AppTheme.beltBlue),
              SizedBox(width: 6),
              Text(
                'PLAYBOOK FAIXA-AZUL',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  color: AppTheme.beltBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Fase clássica de estagnação pós-promoção. O jogo aqui é '
            'reconhecimento + desafio técnico — o WhatsApp deste card já vai '
            'no tom certo, sem cobrar presença.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              fontWeight: FontWeight.w500,
              color: Brand.ink,
            ),
          ),
          const SizedBox(height: 10),
          if (goal == null)
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: const Icon(LucideIcons.target,
                    size: 14, color: AppTheme.beltBlue),
                label: const Text('DEFINIR META TÉCNICA'),
                labelStyle: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                  color: AppTheme.beltBlue,
                ),
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: AppTheme.beltBlue.withValues(alpha: 0.45),
                ),
                visualDensity: VisualDensity.compact,
                onPressed: _onDefineGoal,
              ),
            )
          else
            // Meta já ativa: mostra e deixa editar/concluir no mesmo dialog.
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _onDefineGoal,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(LucideIcons.target,
                        size: 14, color: AppTheme.beltBlue),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            goal.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Brand.ink,
                            ),
                          ),
                          if (goal.until != null)
                            Text(
                              'até ${DateFormat('dd/MM/yy').format(goal.until!)}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Brand.ash.withValues(alpha: 0.9),
                                fontFeatures: Brand.tabular,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'EDITAR',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                        color: AppTheme.beltBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final level = _effectiveLevel;
    final levelColor = level != null ? _levelColor(level) : Brand.ash;
    final days = student.daysSinceLastAttendance;
    final beltLabel = BeltConstants.beltLabels[student.currentBelt.toLowerCase()];
    final hasPhone = _waPhone != null;
    final hasAccount = student.linkedUserId != null;

    // Chip "sugerir inativar": >45 dias sem presença E sem contato pendente.
    final pendingIds =
        ref.watch(retentionPendingContactIdsProvider).valueOrNull;
    final suggestInactivate = days != null &&
        days > 45 &&
        pendingIds != null &&
        !pendingIds.contains(student.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Brand.ash.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Identidade + badge + expandir — tap no aluno abre a ficha.
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            onTap: () => context.push('/admin/alunos/${student.id}'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: levelColor.withValues(alpha: 0.10),
                      border: Border.all(color: levelColor, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      student.fullName.isNotEmpty
                          ? student.fullName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: levelColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: Brand.ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            if (beltLabel != null) ...[
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color:
                                      AppTheme.getBeltColor(student.currentBelt),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Brand.ash.withValues(alpha: 0.4),
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                beltLabel,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Brand.ash,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Text(
                                '  ·  ',
                                style:
                                    TextStyle(fontSize: 11.5, color: Brand.ash),
                              ),
                            ],
                            Flexible(
                              child: Text(
                                days == null
                                    ? 'sem presença registrada'
                                    : 'há $days dia${days == 1 ? '' : 's'} sem treinar',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: levelColor,
                                  fontFeatures: Brand.tabular,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (level != null) _LevelBadge(level: level),
                  if (_isBlues)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: _BluesChip(),
                    ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      _expanded
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      size: 18,
                      color: Brand.ash,
                    ),
                    tooltip: _expanded
                        ? 'Fechar'
                        : _isBlues
                            ? 'Playbook + histórico de contatos'
                            : 'Histórico de contatos',
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
                ],
              ),
            ),
          ),

          // Mini-strip das 8 semanas.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
            child: _WeekMiniStrip(
              buckets: student.last8WeeksBuckets(DateTime.now()),
            ),
          ),

          if (suggestInactivate)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: const Icon(LucideIcons.userX,
                      size: 14, color: Brand.blood),
                  label: const Text('SUGERIR INATIVAR'),
                  labelStyle: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: Brand.blood,
                  ),
                  backgroundColor: Brand.blood.withValues(alpha: 0.06),
                  side: BorderSide(color: Brand.blood.withValues(alpha: 0.35)),
                  visualDensity: VisualDensity.compact,
                  onPressed: _onSuggestInactivate,
                ),
              ),
            ),

          Divider(height: 1, color: Brand.ash.withValues(alpha: 0.12)),

          // As 3 ações do radar.
          Row(
            children: [
              _CardAction(
                icon: LucideIcons.messageCircle,
                label: 'WHATSAPP',
                enabled: hasPhone && !_busy,
                disabledTooltip:
                    hasPhone ? null : 'Aluno sem telefone cadastrado',
                onTap: _onWhatsApp,
              ),
              _actionDivider(),
              _CardAction(
                icon: LucideIcons.bellRing,
                label: 'PUSH',
                enabled: hasAccount && !_busy,
                disabledTooltip:
                    hasAccount ? null : 'Aluno sem conta vinculada no app',
                onTap: _onPush,
              ),
              _actionDivider(),
              _CardAction(
                icon: LucideIcons.clipboardCheck,
                label: 'REGISTRAR',
                enabled: !_busy,
                onTap: _onManualContact,
              ),
            ],
          ),

          // Expandir: playbook blues (quando aplicável) + histórico de contatos.
          if (_expanded) ...[
            Divider(height: 1, color: Brand.ash.withValues(alpha: 0.12)),
            if (_isBlues) _buildBluesPlaybook(),
            _ContactHistory(studentId: student.id),
          ],
        ],
      ),
    );
  }

  Widget _actionDivider() => Container(
        width: 1,
        height: 26,
        color: Brand.ash.withValues(alpha: 0.12),
      );
}

/// Template de WhatsApp por banda de inatividade — voz do PROFESSOR,
/// acolhedora, com nome do aluno e da academia. Nunca culpa.
class _WaTemplate {
  final String id;
  final String Function(String firstName, String academyName) build;
  const _WaTemplate(this.id, this.build);
}

class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.disabledTooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final String? disabledTooltip;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? Brand.ink : Brand.ash.withValues(alpha: 0.4);
    Widget child = InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
    if (!enabled && disabledTooltip != null) {
      child = Tooltip(
        message: disabledTooltip!,
        triggerMode: TooltipTriggerMode.tap,
        child: child,
      );
    }
    return Expanded(child: child);
  }
}

/// Chip discreto "BLUES" (azul-faixa) — qualificador anti-"blue belt blues"
/// (§6.3) ao lado do badge de risco. Mesmo molde visual do [_LevelBadge].
class _BluesChip extends StatelessWidget {
  const _BluesChip();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Faixa-azul esfriando — expanda o card pro playbook próprio',
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.beltBlue.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'BLUES',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
            color: AppTheme.beltBlue,
          ),
        ),
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});

  final String level;

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _levelLabel(level),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Mini-strip das últimas 8 semanas (barras minúsculas, estilo Jornada)
// ════════════════════════════════════════════════════════════════════════════

class _WeekMiniStrip extends StatelessWidget {
  const _WeekMiniStrip({required this.buckets});

  /// 8 posições em ordem cronológica (índice 0 = semana mais antiga).
  final List<int> buckets;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 18,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < buckets.length; i++)
                Expanded(
                  child: Container(
                    height: 3.0 + buckets[i].clamp(0, 4) * 3.5,
                    margin: EdgeInsets.only(
                      right: i < buckets.length - 1 ? 3 : 0,
                    ),
                    decoration: BoxDecoration(
                      color: buckets[i] > 0
                          ? Brand.ink
                          : Brand.ash.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '8 SEM ATRÁS',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: Brand.ash.withValues(alpha: 0.7),
              ),
            ),
            const Text(
              'AGORA',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: Brand.blood,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Histórico de contatos do aluno (expandir do card)
// ════════════════════════════════════════════════════════════════════════════

class _ContactHistory extends ConsumerWidget {
  const _ContactHistory({required this.studentId});

  final String studentId;

  static String _channelLabel(String channel) {
    switch (channel) {
      case 'whatsapp':
        return 'WhatsApp';
      case 'push':
        return 'Push';
      case 'phone':
        return 'Telefone';
      case 'inperson':
        return 'Pessoalmente';
      default:
        return channel;
    }
  }

  static IconData _channelIcon(String channel) {
    switch (channel) {
      case 'whatsapp':
        return LucideIcons.messageCircle;
      case 'push':
        return LucideIcons.bellRing;
      case 'phone':
        return LucideIcons.phone;
      case 'inperson':
        return LucideIcons.users;
      default:
        return LucideIcons.messageSquare;
    }
  }

  static String _ago(DateTime? d) {
    if (d == null) return 'agora';
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    if (days <= 0) return 'hoje';
    if (days == 1) return 'ontem';
    if (days < 30) return 'há $days dias';
    final m = (days / 30).floor();
    return m == 1 ? 'há 1 mês' : 'há $m meses';
  }

  static (String, Color) _outcomeChip(RetentionContact c) {
    if (c.isRecovered) return ('VOLTOU', AppTheme.success);
    if (c.isLost) return ('NÃO VOLTOU', Brand.blood);
    return ('EM ABERTO', Brand.ash);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(studentRetentionContactsProvider(studentId));

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: contactsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (_, _) => const Text(
          'Não deu pra carregar o histórico.',
          style: TextStyle(fontSize: 12, color: Brand.ash),
        ),
        data: (contacts) {
          if (contacts.isEmpty) {
            return const Text(
              'Nenhum contato registrado ainda.',
              style: TextStyle(
                fontSize: 12,
                color: Brand.ash,
                fontWeight: FontWeight.w600,
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ÚLTIMOS CONTATOS',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  color: Brand.ash,
                ),
              ),
              const SizedBox(height: 8),
              ...contacts.map((c) {
                final (label, color) = _outcomeChip(c);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(_channelIcon(c.channel), size: 14, color: Brand.ash),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_channelLabel(c.channel)} · ${_ago(c.at)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Brand.ink,
                              ),
                            ),
                            if (c.note != null && c.note!.isNotEmpty)
                              Text(
                                c.note!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Brand.ash,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Helpers de nível de risco
// ════════════════════════════════════════════════════════════════════════════

/// Laranja de risco ALTO (semântico, não é marca).
const Color _kHighColor = Color(0xFFEA580C);

/// Âmbar de risco MÉDIO (semântico, não é marca).
const Color _kMediumColor = Color(0xFFD97706);

Color _levelColor(String level) {
  switch (level) {
    case 'critical':
      return Brand.blood;
    case 'high':
      return _kHighColor;
    case 'medium':
      return _kMediumColor;
    default:
      return AppTheme.success;
  }
}

String _levelLabel(String level) {
  switch (level) {
    case 'critical':
      return 'CRÍTICO';
    case 'high':
      return 'ALTO';
    case 'medium':
      return 'MÉDIO';
    default:
      return 'BAIXO';
  }
}
