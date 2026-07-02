import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/feed_post.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friend_providers.dart';
import '../../providers/portal_providers.dart';
import '../../providers/student_provider.dart';
import '../../services/feed_posts_service.dart';
import '../../services/settings_service.dart';
import '../../services/streak_freeze_service.dart';
import '../../services/weekly_streak.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/polish/polish.dart';

// =============================================================================
// Tokens anti-slop. Bone + ink + UM acento vermelho. A COR DA FAIXA do lutador
// é usada como acento secundário (é "a cor dele"), nunca cores soltas.
// =============================================================================
class _T {
  _T._();
  static const bone = Color(0xFFF4F3EF);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF0A0A0A);
  static const blood = Color(0xFFE0301E);
  static const smoke = Color(0xFF6E6E68);
  static const ash = Color(0xFF9A9A93);
  static const List<FontFeature> tab = [FontFeature.tabularFigures()];
}

TextStyle _eyebrow(Color c, double s) => TextStyle(
    color: c, fontSize: s, fontWeight: FontWeight.w800, letterSpacing: 1.4);

Color _onBelt(Color belt) =>
    belt.computeLuminance() > 0.6 ? _T.ink : Colors.white;

/// Data curta pt-BR ('15 AGO'; ganha o ano quando não é o corrente).
String _shortDatePt(DateTime d) {
  const m = [
    'JAN', 'FEV', 'MAR', 'ABR', 'MAI', 'JUN', //
    'JUL', 'AGO', 'SET', 'OUT', 'NOV', 'DEZ',
  ];
  final s = '${d.day} ${m[d.month - 1]}';
  return d.year == DateTime.now().year ? s : '$s ${d.year}';
}

String _nameInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) {
    final p = parts.first;
    return p.substring(0, p.length >= 2 ? 2 : 1).toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

/// Hub de identidade do lutador — a aba "Lutador" (dashboard).
class LutadorHubScreen extends ConsumerStatefulWidget {
  const LutadorHubScreen({super.key});

  @override
  ConsumerState<LutadorHubScreen> createState() => _LutadorHubScreenState();
}

class _LutadorHubScreenState extends ConsumerState<LutadorHubScreen> {
  SportId? _selectedSport;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final student = ref.watch(currentStudentProvider).valueOrNull;

    final sports = student?.getSports() ?? const <SportId>[];
    final primary = student?.getPrimarySport() ?? SportId.bjj;
    final sport = (_selectedSport != null && sports.contains(_selectedSport))
        ? _selectedSport!
        : primary;
    final grade = student?.getGrade(sport);
    final belt = grade?.currentGrade ??
        student?.currentBelt ??
        user?.highestBelt ??
        'white';
    final stripes = grade?.currentStripes ??
        student?.currentStripes ??
        user?.highestStripes ??
        0;
    final beltColor = AppTheme.getBeltColor(belt);

    final name = (student?.nickname != null && student!.nickname!.isNotEmpty)
        ? student.nickname!
        : (student?.fullName ?? user?.displayName ?? 'Lutador');

    // ATIVAÇÃO 1ª SESSÃO (§2.1): zero treinos verificados E zero histórico de
    // streak (presença ∪ self-log) → o espaço streak/stats vira UM convite ao
    // 1º registro. É um ESTADO: some para sempre depois do 1º treino.
    final streakInfo = student == null
        ? null
        : ref.watch(studentStreakInfoProvider(student.id)).valueOrNull;
    final isFirstStep = student != null &&
        streakInfo != null &&
        student.totalAttendanceCount == 0 &&
        streakInfo.currentWeeks == 0 &&
        streakInfo.recordWeeks == 0;

    return Scaffold(
      backgroundColor: _T.bone,
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          children: [
            _Header(
              name: name,
              belt: belt,
              stripes: stripes,
              beltColor: beltColor,
              sport: sport,
              photoUrl: student?.photoUrl,
              canSwitch: sports.length > 1,
              onSwitchSport: sports.length > 1
                  ? () {
                      final i = sports.indexOf(sport);
                      setState(() =>
                          _selectedSport = sports[(i + 1) % sports.length]);
                    }
                  : null,
            ),
            const SizedBox(height: 18),
            if (student == null) ...[
              _emptyStreak(),
              const SizedBox(height: 14),
              _unlinked(),
            ] else if (isFirstStep) ...[
              const _FirstStepCard(),
              const SizedBox(height: 22),
              _FriendsSection(),
            ] else ...[
              _StreakCard(studentId: student.id),
              const SizedBox(height: 14),
              _MissionCard(goal: student.activeGoal),
              _GraduationCard(
                studentId: student.id,
                sport: sport,
                belt: belt,
                stripes: stripes,
                beltColor: beltColor,
              ),
              _StatsCard(student: student, beltColor: beltColor),
              const SizedBox(height: 22),
              _FriendsSection(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyStreak() => _DarkCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SEM SEQUÊNCIA ATIVA', style: _eyebrow(_T.ash, 12)),
                  const SizedBox(height: 8),
                  const Text('TREINE ESSA SEMANA\nPRA ACENDER A CORRENTE.',
                      style: TextStyle(
                          color: _T.bone,
                          height: 1.1,
                          fontSize: 20,
                          letterSpacing: 0.2,
                          fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            const Icon(LucideIcons.flame, color: _T.blood, size: 36),
          ],
        ),
      );

  Widget _unlinked() => _WhiteCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SUA IDENTIDADE É SUA', style: _eyebrow(_T.ink, 13)),
            const SizedBox(height: 8),
            Text(
              'Ela anda com você, com ou sem academia. Vincule a uma academia '
              'pra somar treinos, graus e medalhas.',
              style: TextStyle(color: _T.smoke, fontSize: 13.5, height: 1.4),
            ),
          ],
        ),
      );
}

// =============================================================================
// HEADER — avatar + nome + faixa (trocável) + sino.
// =============================================================================
class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.belt,
    required this.stripes,
    required this.beltColor,
    required this.sport,
    required this.canSwitch,
    required this.onSwitchSport,
    this.photoUrl,
  });

  final String name;
  final String belt;
  final int stripes;
  final Color beltColor;
  final SportId sport;
  final bool canSwitch;
  final VoidCallback? onSwitchSport;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final gradeLabel = getGradeLabel(sport, belt);
    final stripeLabel =
        stripes > 0 ? ' · ${stripes == 1 ? '1º grau' : '$stripesº grau'}' : '';
    final initials = _nameInitials(name);
    final onBelt = _onBelt(beltColor);
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: beltColor,
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: (photoUrl != null && photoUrl!.isNotEmpty)
              ? AppCachedImage(
                  imageUrl: photoUrl,
                  width: 54,
                  height: 54,
                  fit: BoxFit.cover,
                  errorIcon: Text(initials,
                      style: TextStyle(
                          color: onBelt,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5)),
                )
              : Text(
                  initials,
                  style: TextStyle(
                    color: onBelt,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _T.ink,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 4),
              Pressable(
                onTap: onSwitchSport,
                child: Row(
                  children: [
                    _MiniBelt(beltColor: beltColor, stripes: stripes),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '$gradeLabel$stripeLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _T.smoke,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (canSwitch) ...[
                      const SizedBox(width: 4),
                      const Icon(LucideIcons.chevronsUpDown,
                          size: 15, color: _T.smoke),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Pressable(
          onTap: () => context.push('/portal/notificacoes'),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _T.card,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(LucideIcons.bell, size: 20, color: _T.ink),
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: _T.blood, shape: BoxShape.circle),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

}

class _MiniBelt extends StatelessWidget {
  const _MiniBelt({required this.beltColor, required this.stripes});
  final Color beltColor;
  final int stripes;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 14,
      decoration: BoxDecoration(
        color: beltColor,
        borderRadius: BorderRadius.circular(3),
      ),
      alignment: Alignment.centerRight,
      child: Container(
        width: 11,
        height: 14,
        decoration: const BoxDecoration(
          color: _T.ink,
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(3),
            bottomRight: Radius.circular(3),
          ),
        ),
        child: stripes > 0
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  stripes.clamp(0, 4),
                  (_) => Container(
                    width: 1.4,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 0.6),
                    color: Colors.white,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

// =============================================================================
// STREAK CARD (dark) — sequência + recorde + a semana. FREEZE (§6.4): a semana
// corrente pode ser PROTEGIDA (lesão/descanso) — não conta como treinada, mas
// não quebra a corrente. Nunca quebra silenciosa; nunca cobrança. A ação é
// discreta: snowflake no canto ou long-press no card.
// =============================================================================
class _StreakCard extends ConsumerStatefulWidget {
  const _StreakCard({required this.studentId});
  final String studentId;

  @override
  ConsumerState<_StreakCard> createState() => _StreakCardState();
}

class _StreakCardState extends ConsumerState<_StreakCard> {
  /// Override OTIMISTA do congelamento da semana corrente (rollback no erro).
  bool? _frozenOverride;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    // Streak SEMANAL: uma SEMANA (seg→dom) conta se teve >=1 treino (presença
    // ou self-log). `currentWeeks` = semanas consecutivas até a atual (com
    // GRACE: a atual sem treino fica pendente, não quebra). `weeks` = strip das
    // últimas ~8 semanas (antiga → atual).
    final info =
        ref.watch(studentStreakInfoProvider(widget.studentId)).valueOrNull;
    final current = info?.currentWeeks ?? 0;
    final record = info?.recordWeeks ?? 0;
    final weeks = info?.weeks ?? const <WeekCell>[];

    // Nenhum treino em todo o histórico (record acumula tudo) → estado zero.
    if (record == 0 && current == 0) return _zeroState();

    // `frozenWeeksProvider` = espelho ao vivo de `users/{uid}.streakFreezes`
    // ('YYYY-Www' → 'lesao'|'descanso'). Só a chave da semana CORRENTE importa
    // aqui — o cálculo de ponte acontece no provider do streak.
    final frozenWeeks = ref.watch(frozenWeeksProvider).valueOrNull ??
        const <String, String>{};
    final frozen = _frozenOverride ??
        frozenWeeks.containsKey(isoWeekKeyOf(DateTime.now()));

    return GestureDetector(
      onLongPress: () => _openFreezeSheet(frozen),
      child: _DarkCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                      frozen
                          ? 'SEQUÊNCIA'
                          : (current > 0 ? 'SEQUÊNCIA ATIVA' : 'SEQUÊNCIA'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _eyebrow(_T.ash, 12)),
                ),
                if (frozen) ...[
                  // Chip discreto de semana protegida — toca pra reativar.
                  const SizedBox(width: 8),
                  Pressable(
                    onTap: () => _openFreezeSheet(true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.snowflake,
                              size: 10, color: _T.bone),
                          const SizedBox(width: 4),
                          Text('SEMANA PROTEGIDA',
                              style: _eyebrow(_T.bone, 10)),
                        ],
                      ),
                    ),
                  ),
                ] else if (record > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _T.blood.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child:
                        Text('RECORDE $record', style: _eyebrow(_T.blood, 10)),
                  ),
                ],
                const Spacer(),
                // Ação discreta de freeze — presença mínima, mas descobrível
                // (long-press no card leva ao mesmo lugar).
                Pressable(
                  onTap: () => _openFreezeSheet(frozen),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(LucideIcons.snowflake,
                        size: 15,
                        color: frozen
                            ? _T.bone
                            : Colors.white.withValues(alpha: 0.35)),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(LucideIcons.flame, color: _T.blood, size: 26),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('$current',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 52,
                        height: 1.0,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -2,
                        fontFeatures: _T.tab)),
                const SizedBox(width: 12),
                Text(current == 1 ? 'SEMANA\nSEGUIDA' : 'SEMANAS\nSEGUIDAS',
                    style: const TextStyle(
                        color: _T.blood,
                        fontSize: 15,
                        height: 1.1,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 18),
            if (weeks.isNotEmpty) _WeekStrip(weeks: weeks),
          ],
        ),
      ),
    );
  }

  /// Sheet fighter-style de PROTEÇÃO DA SEMANA (§6.4 — freeze explícito de
  /// lesão/descanso). Copy acolhedora: proteger nunca soa como falha.
  Future<void> _openFreezeSheet(bool frozen) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _T.ink,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
              child: Row(
                children: [
                  const Icon(LucideIcons.snowflake, size: 18, color: _T.blood),
                  const SizedBox(width: 10),
                  Text(frozen ? 'SEMANA PROTEGIDA' : 'PROTEGER A SEMANA',
                      style: const TextStyle(
                          color: _T.bone,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
              child: Text(
                frozen
                    ? 'Essa semana não quebra tua corrente. Reativa quando '
                        'voltar ao tatame.'
                    : 'Seu streak fica protegido. Volta quando der.',
                style: TextStyle(
                    color: _T.ash,
                    fontSize: 13.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600),
              ),
            ),
            if (frozen)
              _freezeOption(c,
                  icon: LucideIcons.flame,
                  label: 'REATIVAR A SEMANA',
                  sub: 'voltar a contar a partir de agora',
                  value: 'unfreeze')
            else ...[
              _freezeOption(c,
                  icon: LucideIcons.moon,
                  label: 'SEMANA DE DESCANSO',
                  sub: 'recuperar também faz parte do jogo',
                  value: StreakFreezeService.reasonDescanso),
              _freezeOption(c,
                  icon: LucideIcons.heartPulse,
                  label: 'LESIONADO',
                  sub: 'cuida de ti primeiro — sem pressa',
                  value: StreakFreezeService.reasonLesao),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'unfreeze') {
      await _setFrozen(frozen: false);
    } else {
      await _setFrozen(frozen: true, reason: choice);
    }
  }

  Widget _freezeOption(
    BuildContext sheetContext, {
    required IconData icon,
    required String label,
    required String sub,
    required String value,
  }) {
    return Pressable(
      onTap: () => Navigator.pop(sheetContext, value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 19, color: _T.bone),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: _T.bone,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: TextStyle(
                          color: _T.ash,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Congela/descongela a semana ISO corrente — OTIMISTA com rollback no erro.
  /// Invalida o streak: semana protegida não conta como treinada, mas vira
  /// PONTE (não quebra a continuidade).
  Future<void> _setFrozen({required bool frozen, String? reason}) async {
    if (_busy) return;
    final uid = ref.read(currentUserProvider).valueOrNull?.id;
    if (uid == null || uid.isEmpty) return;
    final prev = _frozenOverride;
    setState(() {
      _busy = true;
      _frozenOverride = frozen;
    });
    try {
      final service = StreakFreezeService(uid);
      if (frozen) {
        await service
            .freezeCurrentWeek(reason ?? StreakFreezeService.reasonDescanso);
      } else {
        await service.unfreezeCurrentWeek();
      }
      ref.invalidate(frozenWeeksProvider);
      ref.invalidate(studentStreakInfoProvider(widget.studentId));
    } catch (_) {
      if (mounted) {
        setState(() => _frozenOverride = prev);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Não deu pra atualizar a proteção agora. Tenta de novo.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _zeroState() => _DarkCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SEM SEQUÊNCIA ATIVA', style: _eyebrow(_T.ash, 12)),
                  const SizedBox(height: 8),
                  const Text('TREINE ESSA SEMANA\nPRA ACENDER A CORRENTE.',
                      style: TextStyle(
                          color: _T.bone,
                          height: 1.1,
                          fontSize: 20,
                          letterSpacing: 0.2,
                          fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            const Icon(LucideIcons.flame, color: _T.blood, size: 36),
          ],
        ),
      );
}

// Strip SEMANAL — cada quadrado é uma semana; preenchido = teve treino; a
// semana atual é destacada (pendente = contorno vermelho, treinada = anel).
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.weeks});
  final List<WeekCell> weeks;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < weeks.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < weeks.length - 1 ? 6 : 0),
                  child: _cell(weeks[i]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${weeks.length} SEM ATRÁS', style: _eyebrow(_T.ash, 9)),
            Text('AGORA', style: _eyebrow(_T.blood, 9)),
          ],
        ),
      ],
    );
  }

  Widget _cell(WeekCell w) {
    final pending = w.isCurrent && !w.trained;
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: w.trained ? _T.blood : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: w.isCurrent
              ? Border.all(
                  color: w.trained
                      ? Colors.white.withValues(alpha: 0.85)
                      : _T.blood.withValues(alpha: 0.7),
                  width: 1.6,
                )
              : null,
        ),
        child: pending
            ? Center(
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: _T.blood,
                    shape: BoxShape.circle,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

// =============================================================================
// ATIVAÇÃO 1ª SESSÃO (§2.1) — zero treinos: o espaço do streak/stats vira UM
// convite ao 1º registro (1 ação significativa na 1ª sessão ≈ 2-3x retenção).
// É um convite, não um tutorial — e some para sempre depois do 1º treino.
// =============================================================================
class _FirstStepCard extends StatelessWidget {
  const _FirstStepCard();

  @override
  Widget build(BuildContext context) {
    return _DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('PRIMEIRO PASSO', style: _eyebrow(_T.ash, 12)),
              const Spacer(),
              const Icon(LucideIcons.flame, color: _T.blood, size: 26),
            ],
          ),
          const SizedBox(height: 10),
          const Text('REGISTRA TEU\nPRIMEIRO TREINO.',
              style: TextStyle(
                  color: _T.bone,
                  height: 1.1,
                  fontSize: 22,
                  letterSpacing: 0.2,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            'Leva 5 segundos — e é aqui que a tua corrente acende.',
            style: TextStyle(
                color: _T.ash,
                fontSize: 13.5,
                height: 1.4,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Pressable(
            onTap: () => context.go('/portal/diario'),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                  color: _T.blood, borderRadius: BorderRadius.circular(8)),
              alignment: Alignment.center,
              child: const Text('REGISTRAR TREINO',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0)),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// MISSÃO ATIVA (anti-blues §6.3, arma 1) — meta técnica de curto prazo que o
// PROFESSOR definiu. É um ESTADO, não uma seção: invisível sem meta (ou com
// meta vencida — missão velha nunca vira cobrança).
// =============================================================================
class _MissionCard extends StatelessWidget {
  const _MissionCard({required this.goal});
  final StudentGoal? goal;

  @override
  Widget build(BuildContext context) {
    final g = goal;
    if (g == null || g.text.trim().isEmpty) return const SizedBox.shrink();
    final until = g.until;
    if (until != null) {
      final endOfDay = DateTime(until.year, until.month, until.day, 23, 59, 59);
      if (DateTime.now().isAfter(endOfDay)) return const SizedBox.shrink();
    }
    final signedBy = g.setByName?.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _T.card,
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: _T.blood.withValues(alpha: 0.22), width: 1.2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _T.blood.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: const Icon(LucideIcons.target, size: 20, color: _T.blood),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('MISSÃO DO PROFESSOR',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _eyebrow(_T.blood, 10.5)),
                      ),
                      if (until != null)
                        Text('ATÉ ${_shortDatePt(until)}',
                            style: _eyebrow(_T.ash, 10)),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(g.text.trim(),
                      style: const TextStyle(
                          color: _T.ink,
                          fontSize: 15,
                          height: 1.35,
                          fontWeight: FontWeight.w800)),
                  if (signedBy != null && signedBy.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('— $signedBy',
                        style: const TextStyle(
                            color: _T.smoke,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// GRADUATION CARD — só se a academia liga graduação-por-presença E o progresso
// é público pro aluno.
// =============================================================================
class _GraduationCard extends ConsumerWidget {
  const _GraduationCard({
    required this.studentId,
    required this.sport,
    required this.belt,
    required this.stripes,
    required this.beltColor,
  });
  final String studentId;
  final SportId sport;
  final String belt;
  final int stripes;
  final Color beltColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(academySettingsProvider).valueOrNull;
    final gate = settings is AcademySettings &&
        settings.autoGraduationEnabled &&
        settings.graduationProgressVisibleToStudents;
    if (!gate) return const SizedBox.shrink();

    final elig = ref
        .watch(studentSportEligibilityProvider(
            (studentId: studentId, sport: sport)))
        .valueOrNull;
    if (elig == null || elig.requiredClasses <= 0) {
      return const SizedBox.shrink();
    }
    final pct = (elig.currentClasses / elig.requiredClasses).clamp(0.0, 1.0);
    final pctLabel = (pct * 100).round();
    final gradeLabel = getGradeLabel(sport, belt);
    final nextLabel = elig.eligible ? 'pronto!' : 'próximo grau';
    final accent = beltColor.computeLuminance() > 0.82 ? _T.ink : beltColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _WhiteCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _MiniBelt(beltColor: beltColor, stripes: stripes),
                const SizedBox(width: 8),
                Text(gradeLabel,
                    style: const TextStyle(
                        color: _T.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w900)),
                const Spacer(),
                Text('$pctLabel% → $nextLabel',
                    style: TextStyle(
                        color: accent,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                backgroundColor: _T.ink.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// STATS CARD — treinos | este mês | #rank.
// =============================================================================
class _StatsCard extends ConsumerWidget {
  const _StatsCard({required this.student, required this.beltColor});
  final Student student;
  final Color beltColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final treinos = student.totalAttendanceCount;
    final mes =
        ref.watch(studentMonthlyAttendanceProvider(student.id)).valueOrNull;
    final rank = ref.watch(studentMonthlyRankProvider(student.id)).valueOrNull;
    final rankColor = beltColor.computeLuminance() > 0.82 ? _T.ink : beltColor;

    return _WhiteCard(
      child: Row(
        children: [
          Expanded(child: _statVerificado('$treinos')),
          _divider(),
          Expanded(
              child: _stat(mes == null ? '—' : '$mes', 'ESTE MÊS', _T.ink)),
          _divider(),
          Expanded(
              child: _stat(
                  rank == null ? '—' : '#$rank', 'NA ACADEMIA', rankColor)),
        ],
      ),
    );
  }

  Widget _divider() =>
      Container(width: 1, height: 40, color: _T.ink.withValues(alpha: 0.08));

  Widget _stat(String value, String label, Color color) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 30,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  fontFeatures: _T.tab)),
          const SizedBox(height: 5),
          Text(label, textAlign: TextAlign.center, style: _eyebrow(_T.smoke, 10)),
        ],
      );

  /// Variante para "AULAS VERIFICADAS" — exibe ícone de check discreto
  /// ao lado do rótulo para sinalizar que são presenças da academia.
  Widget _statVerificado(String value) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: _T.ink,
                  fontSize: 30,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  fontFeatures: _T.tab)),
          const SizedBox(height: 5),
          // Text.rich (não Row): o rótulo é longo e a célula do stat é estreita —
          // com WidgetSpan o ícone acompanha o texto e a linha QUEBRA graciosa
          // em telas estreitas em vez de estourar (RenderFlex overflow).
          Text.rich(
            TextSpan(children: [
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: EdgeInsets.only(right: 3),
                  child:
                      Icon(Icons.verified_outlined, size: 10, color: _T.smoke),
                ),
              ),
              TextSpan(text: 'AULAS VERIFICADAS'),
            ]),
            textAlign: TextAlign.center,
            style: _eyebrow(_T.smoke, 9),
          ),
        ],
      );
}

// =============================================================================
// FRIENDS — preview do feed de AMIGOS (não a academia toda). Com ≥1 amigo,
// mostra a ATIVIDADE RECENTE (top 3); sem amigos, o convite p/ adicionar.
// =============================================================================
class _FriendsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audienceAsync = ref.watch(myPartnersAudienceProvider);
    // Show the activity card while loading (it handles its own states) or when
    // we have at least one partner (follows ∪ classmates). Show the add-partners
    // CTA only when the audience is definitively resolved and empty.
    final hasPartners = audienceAsync.isLoading ||
        (audienceAsync.valueOrNull?.isNotEmpty ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(width: 14, height: 2, color: _T.blood),
            const SizedBox(width: 8),
            Text('PARCEIROS', style: _eyebrow(_T.ink, 13)),
            const Spacer(),
            Pressable(
              onTap: () => context.go('/portal/cena'),
              child: const Text('ver tudo',
                  style: TextStyle(
                      color: _T.smoke,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (hasPartners) _FriendsActivityCard() else _addFriendsCard(context),
      ],
    );
  }

  Widget _addFriendsCard(BuildContext context) => _WhiteCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SEUS PARCEIROS DE TREINO', style: _eyebrow(_T.ink, 12)),
            const SizedBox(height: 8),
            Text(
              'Adicione parceiros de treino — da sua academia ou de qualquer '
              'outra — e veja os treinos deles aqui. Sem mar de notificação: '
              'só quem você escolhe.',
              style: TextStyle(color: _T.smoke, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            Pressable(
              onTap: () => context.go('/portal/cena'),
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                    color: _T.ink, borderRadius: BorderRadius.circular(8)),
                alignment: Alignment.center,
                child: const Text('VER PARCEIROS',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0)),
              ),
            ),
          ],
        ),
      );
}

/// Card de ATIVIDADE RECENTE dos parceiros (top 3 posts), via [feedPostsProvider].
class _FriendsActivityCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_FriendsActivityCard> createState() =>
      _FriendsActivityCardState();
}

class _FriendsActivityCardState extends ConsumerState<_FriendsActivityCard> {
  @override
  Widget build(BuildContext context) {
    final posts =
        ref.watch(feedPostsProvider).valueOrNull ?? const <FeedPost>[];
    if (posts.isEmpty) {
      return _WhiteCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _T.ink.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child:
                  const Icon(LucideIcons.users, size: 20, color: _T.smoke),
            ),
            const SizedBox(height: 12),
            Text('SEM ATIVIDADE RECENTE', style: _eyebrow(_T.ash, 11)),
            const SizedBox(height: 6),
            Text(
              'Quando seus parceiros treinarem, graduarem ou baterem marco, '
              'aparece aqui.',
              style: TextStyle(color: _T.smoke, fontSize: 13.5, height: 1.4),
            ),
          ],
        ),
      );
    }
    final likedIds =
        ref.watch(likedPostIdsProvider).valueOrNull ?? const <String>{};
    final myUid = ref.watch(currentUserProvider).valueOrNull?.id;
    final top = posts.take(3).toList();
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < top.length; i++) ...[
            if (i > 0)
              Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  color: _T.ink.withValues(alpha: 0.06)),
            _ActivityRow(
              post: top[i],
              likedByMe: likedIds.contains(top[i].postId),
              isMyPost: top[i].authorUid == myUid,
              onLikeToggled: () {
                ref.invalidate(feedPostsProvider);
                ref.invalidate(likedPostIdsProvider);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _ActivityRow extends ConsumerStatefulWidget {
  const _ActivityRow({
    required this.post,
    required this.likedByMe,
    required this.isMyPost,
    required this.onLikeToggled,
  });
  final FeedPost post;
  final bool likedByMe;
  final bool isMyPost;
  final VoidCallback onLikeToggled;

  @override
  ConsumerState<_ActivityRow> createState() => _ActivityRowState();
}

class _ActivityRowState extends ConsumerState<_ActivityRow> {
  late bool _liked;
  late int _likeCount;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _liked = widget.likedByMe;
    _likeCount = widget.post.likeCount;
  }

  @override
  void didUpdateWidget(_ActivityRow old) {
    super.didUpdateWidget(old);
    if (old.likedByMe != widget.likedByMe) _liked = widget.likedByMe;
    if (old.post.likeCount != widget.post.likeCount) {
      _likeCount = widget.post.likeCount;
    }
  }

  Future<void> _toggleLike() async {
    if (widget.isMyPost || _busy) return;
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    setState(() {
      _busy = true;
      if (_liked) {
        _liked = false;
        _likeCount = (_likeCount - 1).clamp(0, 999999);
      } else {
        _liked = true;
        _likeCount += 1;
      }
    });
    try {
      if (_liked) {
        final profile = ref.read(currentStudentProvider).valueOrNull;
        await feedPostsService.like(
          giverUid: me.id,
          postId: widget.post.postId,
          authorUid: widget.post.authorUid,
          giverName: profile?.nickname?.isNotEmpty == true
              ? profile!.nickname!
              : (profile?.fullName ?? 'Lutador'),
          giverBelt: profile?.currentBelt ?? 'white',
          giverStripes: profile?.currentStripes ?? 0,
        );
      } else {
        await feedPostsService.unlike(
            giverUid: me.id, postId: widget.post.postId);
      }
      widget.onLikeToggled();
    } catch (_) {
      if (mounted) {
        setState(() {
          _liked = !_liked;
          _likeCount = widget.post.likeCount;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static IconData _typeIcon(FeedPostType t) => switch (t) {
        FeedPostType.graduacao => LucideIcons.award,
        FeedPostType.competicao => LucideIcons.medal,
        FeedPostType.streakMilestone => LucideIcons.flame,
        FeedPostType.sparringRecord => LucideIcons.zap,
        FeedPostType.weeklyVolume => LucideIcons.activity,
        FeedPostType.matMilestone => LucideIcons.flag,
      };

  static String _ago(DateTime d) {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    if (days <= 0) return 'hoje';
    if (days == 1) return 'ontem';
    if (days < 7) return 'há $days dias';
    if (days < 30) {
      final w = (days / 7).floor();
      return w == 1 ? 'há 1 sem' : 'há $w sem';
    }
    if (days < 365) {
      final m = (days / 30).floor();
      return m == 1 ? 'há 1 mês' : 'há $m meses';
    }
    final y = (days / 365).floor();
    return y == 1 ? 'há 1 ano' : 'há $y anos';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final beltColor = AppTheme.getBeltColor(p.authorBelt);
    final initials = _nameInitials(p.authorName);
    return Pressable(
      onTap: () => context.push('/portal/profile/${p.authorUid}'),
      child: Row(
        children: [
          AppCachedAvatar(
            imageUrl: p.authorPhotoUrl,
            radius: 18,
            backgroundColor: beltColor,
            child: Text(
              initials,
              style: TextStyle(
                color: _onBelt(beltColor),
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.authorName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _T.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        p.headline.toLowerCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _T.smoke,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text('  ·  ${_ago(p.occurredAt)}',
                        style: const TextStyle(
                            color: _T.ash,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            fontFeatures: _T.tab)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Like pill inline.
          if (!widget.isMyPost) ...[
            Pressable(
              onTap: _toggleLike,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_liked ? Icons.favorite : Icons.favorite_border,
                      size: 14,
                      color: _liked ? const Color(0xFFE0301E) : _T.ash),
                  const SizedBox(width: 3),
                  Text('$_likeCount',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          fontFeatures: _T.tab,
                          color: _liked ? const Color(0xFFE0301E) : _T.ash)),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
          Icon(_typeIcon(p.type), size: 18, color: _T.ink),
        ],
      ),
    );
  }
}

// =============================================================================
// Cartões base.
// =============================================================================
class _DarkCard extends StatelessWidget {
  const _DarkCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _T.ink,
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      );
}

class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _T.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      );
}
