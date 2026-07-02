import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/feed_post.dart';
import '../../models/fighter_profile.dart';
import '../../models/ranking_entry.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friend_providers.dart';
import '../../providers/oss_providers.dart';
import '../../providers/portal_providers.dart';
import '../../providers/ranking_providers.dart';
import '../../providers/student_provider.dart';
import '../../services/achievement_service.dart';
import '../../services/competition_service.dart';
import '../../services/feed_posts_service.dart';
import '../../services/friend_service.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/polish/polish.dart';

// =============================================================================
// Paleta consistente com o hub do Lutador. Bone + ink + um acento vermelho.
// =============================================================================
class _C {
  _C._();
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

String _nameInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

enum _Seg { parceiros, academia }

/// GALERA — a aba social. Dividida em PARCEIROS (colegas de turma + follows)
/// e ACADEMIA (ranking, conquistas e campeonatos).
/// Sem ranking global, sem descoberta invasiva.
class CenaScreen extends ConsumerStatefulWidget {
  const CenaScreen({super.key});

  @override
  ConsumerState<CenaScreen> createState() => _CenaScreenState();
}

class _CenaScreenState extends ConsumerState<CenaScreen> {
  _Seg _seg = _Seg.parceiros;
  RankingPeriod _period = RankingPeriod.month;
  // null = GERAL (totalTrainings histórico); não-null = presenças no período.
  RankingPeriod? _partnerPeriod;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bone,
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const Text('GALERA',
                style: TextStyle(
                    color: _C.ink,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5)),
            const SizedBox(height: 14),
            _Segmented(
              seg: _seg,
              onChanged: (s) => setState(() => _seg = s),
            ),
            const SizedBox(height: 18),
            if (_seg == _Seg.academia) ..._academia() else ..._parceiros(),
          ],
        ),
      ),
    );
  }

  // ── ACADEMIA: ranking + feed de posts + conquistas + campeonatos ────────────
  List<Widget> _academia() {
    final myUid = ref.watch(currentUserProvider).valueOrNull?.id;
    final academyFeedAsync = ref.watch(academyFeedPostsProvider);
    final academyLikedAsync = ref.watch(academyLikedPostIdsProvider);

    return [
      Row(
        children: [
          _sectionLabel('RANKING DA ACADEMIA'),
          const Spacer(),
          _PeriodToggle(
            period: _period,
            onChanged: (p) => setState(() => _period = p),
          ),
        ],
      ),
      const SizedBox(height: 10),
      _RankingCard(period: _period),
      const SizedBox(height: 26),

      // ATIVIDADE — feed materializado de posts (academyFeedPostsProvider).
      _sectionLabel('ATIVIDADE DA ACADEMIA'),
      const SizedBox(height: 10),
      academyFeedAsync.when(
        loading: () => const _White(child: _Loading()),
        error: (_, _) =>
            const _White(child: _Voice('Não deu pra carregar a atividade.')),
        data: (posts) {
          if (posts.isEmpty) {
            return const _White(
              child: _Voice(
                'Quando alguém da academia graduar, competir ou bater marco, aparece aqui.',
              ),
            );
          }
          final likedIds = academyLikedAsync.valueOrNull ?? const <String>{};
          return Column(
            children: [
              for (var i = 0; i < posts.length; i++) ...[
                _PostCard(
                  post: posts[i],
                  likedByMe: likedIds.contains(posts[i].postId),
                  isMyPost: posts[i].authorUid == myUid,
                  onLikeToggled: () {
                    ref.invalidate(academyFeedPostsProvider);
                    ref.invalidate(academyLikedPostIdsProvider);
                  },
                  onHidden: () => ref.invalidate(academyFeedPostsProvider),
                ),
                if (i < posts.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
      const SizedBox(height: 26),

      _sectionLabel('CONQUISTAS DA ACADEMIA'),
      const SizedBox(height: 10),
      const _AchievementsFeed(),
      const SizedBox(height: 26),
      Row(
        children: [
          _sectionLabel('CAMPEONATOS'),
          const Spacer(),
          Pressable(
            onTap: () => context.push('/portal/competicoes'),
            child: const Text('ver tudo',
                style: TextStyle(
                    color: _C.smoke,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      const SizedBox(height: 10),
      const _CompetitionsCard(),
    ];
  }

  // ── PARCEIROS: strip + botão add + ranking + feed ─────────────────────────
  List<Widget> _parceiros() {
    final partnersAsync = ref.watch(partnersDisplayProvider);
    final rankAsync = ref.watch(partnersRankingProvider(_partnerPeriod));
    final feedAsync = ref.watch(feedPostsProvider);
    final likedAsync = ref.watch(likedPostIdsProvider);
    final myUid = ref.watch(currentUserProvider).valueOrNull?.id;

    return [
      // (a) HEADER: label + botão ADICIONAR discreto.
      Row(
        children: [
          _sectionLabel('PARCEIROS'),
          const Spacer(),
          Pressable(
            onTap: _showAddFriend,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: _C.ink.withValues(alpha: 0.14)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.userPlus, size: 13, color: _C.smoke),
                  const SizedBox(width: 5),
                  Text('ADICIONAR', style: _eyebrow(_C.smoke, 10)),
                ],
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),

      // (b) STRIP DE PARCEIROS — scroll horizontal (colegas ∪ amigos).
      partnersAsync.when(
        loading: () => const SizedBox(height: 8),
        error: (_, _) => const SizedBox.shrink(),
        data: (partners) {
          if (partners.isEmpty) {
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: _C.ink.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.users, size: 16, color: _C.ash),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Nenhum parceiro ainda.',
                      style: TextStyle(
                          color: _C.smoke,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  Pressable(
                    onTap: _showAddFriend,
                    child: Text('ADICIONAR', style: _eyebrow(_C.blood, 10)),
                  ),
                ],
              ),
            );
          }
          return SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: partners.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final p = partners[i];
                final beltColor = AppTheme.getBeltColor(p.belt);
                final onBelt =
                    beltColor.computeLuminance() > 0.6 ? _C.ink : Colors.white;
                // Navega pelo studentId (colega → perfil intra-academia;
                // amigo → studentId==uid → vitrine do espelho). Isso evita o
                // "Perfil não disponível" que dava ao navegar pelo uid do colega.
                void onTap() => context.push('/portal/profile/${p.studentId}');
                return Pressable(
                  onTap: onTap,
                  child: SizedBox(
                    width: 52,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Avatar(
                          photoUrl: p.photoUrl,
                          initials: _nameInitials(p.name),
                          beltColor: beltColor,
                          onBelt: onBelt,
                          size: 48,
                          radius: 12,
                          fontSize: 15,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          p.name.split(' ').first.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: _C.smoke),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      const SizedBox(height: 22),

      // (c) RANKING DOS PARCEIROS.
      Row(
        children: [
          _sectionLabel('RANKING'),
          const Spacer(),
          _PartnerPeriodToggle(
            period: _partnerPeriod,
            onChanged: (p) => setState(() => _partnerPeriod = p),
          ),
        ],
      ),
      const SizedBox(height: 10),
      _PartnersRankCard(rankAsync: rankAsync, period: _partnerPeriod),
      const SizedBox(height: 26),

      // (d) FEED de atividade dos parceiros.
      _sectionLabel('ATIVIDADE'),
      const SizedBox(height: 10),
      feedAsync.when(
        loading: () => const _White(child: _Loading()),
        error: (_, _) =>
            const _White(child: _Voice('Não deu pra carregar o feed.')),
        data: (posts) {
          if (posts.isEmpty) {
            return const _White(
              child: _Voice(
                'Seus parceiros ainda não postaram. Quando treinarem, graduarem '
                'ou baterem marco, aparece aqui.',
              ),
            );
          }
          final likedIds = likedAsync.valueOrNull ?? const <String>{};
          return Column(
            children: [
              for (var i = 0; i < posts.length; i++) ...[
                _PostCard(
                  post: posts[i],
                  likedByMe: likedIds.contains(posts[i].postId),
                  isMyPost: posts[i].authorUid == myUid,
                  onLikeToggled: () {
                    ref.invalidate(feedPostsProvider);
                    ref.invalidate(likedPostIdsProvider);
                  },
                  onHidden: () => ref.invalidate(feedPostsProvider),
                ),
                if (i < posts.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    ];
  }

  Future<void> _showAddFriend() async {
    final code = ref.read(myFighterCodeProvider).valueOrNull;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _C.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddFriendSheet(
        myCode: code,
        onAdded: (name) {
          ref.invalidate(myFriendsProvider);
          ref.invalidate(partnersDisplayProvider);
          ref.invalidate(partnersRankingProvider);
          _toast('$name adicionado');
        },
      ),
    );
  }

  void _toast(String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(what.toUpperCase(),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
        backgroundColor: _C.ink,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8))),
      ),
    );
  }

  Widget _sectionLabel(String t) => Text(t, style: _eyebrow(_C.ink, 13));
}

// =============================================================================
// Segmented control [ AMIGOS | ACADEMIA ]
// =============================================================================
class _Segmented extends StatelessWidget {
  const _Segmented({required this.seg, required this.onChanged});
  final _Seg seg;
  final ValueChanged<_Seg> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _C.ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _tab('PARCEIROS', _Seg.parceiros),
          _tab('ACADEMIA', _Seg.academia),
        ],
      ),
    );
  }

  Widget _tab(String label, _Seg value) {
    final active = seg == value;
    return Expanded(
      child: Pressable(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? _C.card : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(label,
              style: TextStyle(
                  color: active ? _C.ink : _C.smoke,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8)),
        ),
      ),
    );
  }
}

class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({required this.period, required this.onChanged});
  final RankingPeriod period;
  final ValueChanged<RankingPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget pill(String label, RankingPeriod p) {
      final active = period == p;
      return Pressable(
        onTap: () => onChanged(p),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? _C.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label,
              style: TextStyle(
                  color: active ? Colors.white : _C.smoke,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5)),
        ),
      );
    }

    return Row(children: [
      pill('7 DIAS', RankingPeriod.week),
      const SizedBox(width: 4),
      pill('30 DIAS', RankingPeriod.month),
    ]);
  }
}

// =============================================================================
// Toggle de período para o ranking de PARCEIROS (GERAL / MÊS / SEMANA).
// Usa RankingPeriod? onde null == GERAL.
// Track com fundo cinza-suave + pill animada — padrão fighter mini.
// =============================================================================
class _PartnerPeriodToggle extends StatelessWidget {
  const _PartnerPeriodToggle({required this.period, required this.onChanged});
  final RankingPeriod? period;
  final ValueChanged<RankingPeriod?> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget pill(String label, RankingPeriod? p) {
      final active = period == p;
      return Pressable(
        onTap: () {
          if (period == p) return;
          HapticFeedback.selectionClick();
          onChanged(p);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: active ? _C.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : _C.smoke,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _C.ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pill('GERAL', null),
          pill('30 DIAS', RankingPeriod.month),
          pill('7 DIAS', RankingPeriod.week),
        ],
      ),
    );
  }
}

// =============================================================================
// RANKING da academia
// =============================================================================
class _RankingCard extends ConsumerWidget {
  const _RankingCard({required this.period});
  final RankingPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ALINHA com a tabela completa (/portal/ranking): o aluno vê o ranking da
    // SUA categoria (kids/adult) e da SUA modalidade — não um agregado geral.
    // Sem isso os números divergiam da tabela.
    final student = ref.watch(currentStudentProvider).valueOrNull;
    final category = student == null
        ? RankingCategory.general
        : (student.category == StudentCategory.kids
            ? RankingCategory.kids
            : RankingCategory.adult);
    final sport = student?.getPrimarySport().value;
    final async = ref.watch(classRankingProvider((
      category: category,
      period: period,
      sport: sport,
    )));
    return _White(
      onTap: () => context.push('/portal/ranking'),
      child: async.when(
        loading: () => const _Loading(),
        error: (_, _) => const _Voice('Ranking fora do ar agora.'),
        data: (entries) {
          if (entries.isEmpty) {
            return const _Voice(
                'Ninguém marcou presença ainda. Seja o primeiro.');
          }
          final top = entries.take(5).toList();
          return Column(
            children: [
              for (var i = 0; i < top.length; i++) ...[
                _RankRow(entry: top[i]),
                if (i != top.length - 1)
                  Divider(
                      height: 16,
                      thickness: 1,
                      color: _C.ink.withValues(alpha: 0.06)),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('PRESENÇAS · VER TABELA COMPLETA',
                    style: _eyebrow(_C.ash, 10)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.entry});
  final RankingEntry entry;
  @override
  Widget build(BuildContext context) {
    final leader = entry.rank == 1;
    return Row(
      children: [
        SizedBox(
          width: 30,
          child: Text('${entry.rank}',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                  letterSpacing: -0.5,
                  fontFeatures: _C.tab,
                  color: leader ? _C.blood : _C.ink)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(entry.studentName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: _C.ink)),
        ),
        const SizedBox(width: 8),
        Text('${entry.attendanceCount}',
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                fontFeatures: _C.tab,
                color: _C.ink)),
      ],
    );
  }
}

// =============================================================================
// CONQUISTAS da academia (só conquistas, sem treino do dia)
// =============================================================================
class _AchievementsFeed extends ConsumerWidget {
  const _AchievementsFeed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(academyRecentAchievementsProvider);
    return _White(
      child: async.when(
        loading: () => const _Loading(),
        error: (_, _) => const _Voice('Não deu pra carregar agora.'),
        data: (items) {
          if (items.isEmpty) {
            return const _Voice(
                'As conquistas da academia — graduações e medalhas — aparecem aqui.');
          }
          final shown = items.take(6).toList();
          return Column(
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                _AchRow(a: shown[i]),
                if (i != shown.length - 1)
                  Divider(
                      height: 18,
                      thickness: 1,
                      color: _C.ink.withValues(alpha: 0.06)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AchRow extends StatelessWidget {
  const _AchRow({required this.a});
  final Achievement a;

  @override
  Widget build(BuildContext context) {
    final d = a.date;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(_icon(a.type), size: 18, color: _C.ink),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.studentName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                      color: _C.ink)),
              const SizedBox(height: 2),
              Text(a.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _C.smoke)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(dateStr,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFeatures: _C.tab,
                color: _C.ash)),
      ],
    );
  }

  IconData _icon(AchievementType t) {
    switch (t) {
      case AchievementType.graduation:
        return LucideIcons.award;
      case AchievementType.stripe:
        return LucideIcons.star;
      case AchievementType.competition:
        return LucideIcons.trophy;
      case AchievementType.milestone:
        return LucideIcons.flag;
      case AchievementType.attendanceStreak:
        return LucideIcons.zap;
      case AchievementType.rankingPosition:
        return LucideIcons.barChart2;
      case AchievementType.trainingPr:
        return LucideIcons.trendingUp;
    }
  }
}

// =============================================================================
// CAMPEONATOS
// =============================================================================
class _CompetitionsCard extends ConsumerWidget {
  const _CompetitionsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(upcomingCompetitionsProvider);
    return async.when(
      loading: () => const _White(child: _Loading()),
      error: (_, _) =>
          const _White(child: _Voice('Não deu pra carregar o calendário.')),
      data: (comps) {
        if (comps.isEmpty) {
          return _White(
            onTap: () => context.push('/portal/competicoes'),
            child: const _Voice(
                'Nenhum campeonato marcado. Quando rolar, aparece aqui.'),
          );
        }
        final next = comps.take(3).toList();
        return Column(
          children: [
            for (var i = 0; i < next.length; i++) ...[
              _CompRow(c: next[i]),
              if (i != next.length - 1) const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _CompRow extends StatelessWidget {
  const _CompRow({required this.c});
  final Competition c;

  @override
  Widget build(BuildContext context) {
    final day = DateFormat('d').format(c.date);
    final month = DateFormat('MMM', 'pt_BR').format(c.date).toUpperCase();
    return _White(
      onTap: () => context.push('/portal/competicoes/${c.id}'),
      child: Row(
        children: [
          Container(
            width: 54,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
                color: _C.ink, borderRadius: BorderRadius.circular(8)),
            child: Column(
              children: [
                Text(day,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                        fontFeatures: _C.tab,
                        color: Colors.white)),
                const SizedBox(height: 2),
                Text(month,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: _C.ash)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        color: _C.ink)),
                if (c.location != null && c.location!.trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Row(children: [
                    const Icon(LucideIcons.mapPin, size: 13, color: _C.ash),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(c.location!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: _C.smoke)),
                    ),
                  ]),
                ],
              ],
            ),
          ),
          const Icon(LucideIcons.chevronRight, size: 18, color: _C.ash),
        ],
      ),
    );
  }
}

// =============================================================================
// Sheet de adicionar amigo (StatefulWidget próprio — controller com dispose
// correto; antes o ctrl era disposto manualmente após o await e estourava ao
// fechar a sheet tocando fora).
// =============================================================================
class _AddFriendSheet extends ConsumerStatefulWidget {
  const _AddFriendSheet({required this.onAdded, this.myCode});
  final void Function(String name) onAdded;
  final String? myCode;
  @override
  ConsumerState<_AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends ConsumerState<_AddFriendSheet> {
  final _ctrl = TextEditingController();
  FighterProfile? _found;
  String? _error;
  bool _searching = false;
  bool _adding = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _error = null;
      _found = null;
    });
    final p = await friendService.findByCode(_ctrl.text);
    if (!mounted) return;
    setState(() {
      _searching = false;
      if (p == null) {
        _error = 'Nenhum lutador com esse código.';
      } else {
        _found = p;
      }
    });
  }

  Future<void> _add() async {
    final me = ref.read(currentUserProvider).valueOrNull?.id;
    final p = _found;
    if (me == null || p == null || _adding) return;
    setState(() => _adding = true);
    await friendService.addFriend(myUid: me, targetUid: p.uid);
    if (!mounted) return;
    Navigator.pop(context);
    widget.onAdded(p.name);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, MediaQuery.viewInsetsOf(context).bottom + 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ADICIONAR AMIGO', style: _eyebrow(_C.ink, 13)),
          const SizedBox(height: 14),

          // ── MEU CÓDIGO ────────────────────────────────────────────────────
          if (widget.myCode != null) ...[
            Text('MEU CÓDIGO', style: _eyebrow(_C.ash, 10)),
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _C.ink.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.myCode!,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 5,
                          color: _C.ink),
                    ),
                  ),
                  Pressable(
                    onTap: () {
                      Clipboard.setData(
                          ClipboardData(text: widget.myCode!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('CÓDIGO COPIADO',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800)),
                          backgroundColor: _C.ink,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: const Icon(LucideIcons.copy,
                        size: 17, color: _C.smoke),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Divider(height: 1, color: _C.ink.withValues(alpha: 0.08)),
            const SizedBox(height: 16),
            Text('CÓDIGO DO PARCEIRO', style: _eyebrow(_C.ash, 10)),
            const SizedBox(height: 8),
          ] else ...[
            Text('Digite o código de lutador do seu parceiro.',
                style: const TextStyle(
                    color: _C.smoke,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
          ],

          // ── BUSCA POR CÓDIGO ──────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  onChanged: (_) {
                    if (_found != null || _error != null) {
                      setState(() {
                        _found = null;
                        _error = null;
                      });
                    }
                  },
                  onSubmitted: (_) => _search(),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      letterSpacing: 4,
                      color: _C.ink),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'CÓDIGO',
                    hintStyle:
                        TextStyle(color: _C.ash, letterSpacing: 2, fontSize: 16),
                    filled: true,
                    fillColor: _C.ink.withValues(alpha: 0.04),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Pressable(
                onTap: _searching ? null : _search,
                child: Container(
                  height: 50,
                  width: 50,
                  decoration: BoxDecoration(
                      color: _C.ink, borderRadius: BorderRadius.circular(10)),
                  child: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(15),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(LucideIcons.search,
                          color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(
                    color: _C.blood, fontWeight: FontWeight.w700)),
          ],
          if (_found != null) ...[
            const SizedBox(height: 16),
            _FriendRow(profile: _found!, onRemove: null),
            const SizedBox(height: 14),
            Pressable(
              onTap: _add,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                    color: _C.blood, borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: _adding
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('ADICIONAR',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Card de POST do feed social.
// =============================================================================
class _PostCard extends ConsumerStatefulWidget {
  const _PostCard({
    required this.post,
    required this.likedByMe,
    required this.isMyPost,
    required this.onLikeToggled,
    required this.onHidden,
  });

  final FeedPost post;
  final bool likedByMe;
  final bool isMyPost;
  final VoidCallback onLikeToggled;
  final VoidCallback onHidden;

  @override
  ConsumerState<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<_PostCard> {
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
  void didUpdateWidget(_PostCard old) {
    super.didUpdateWidget(old);
    if (old.likedByMe != widget.likedByMe) {
      _liked = widget.likedByMe;
    }
    if (old.post.likeCount != widget.post.likeCount) {
      _likeCount = widget.post.likeCount;
    }
  }

  Future<void> _toggleLike() async {
    if (_busy) return;
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
        final myBelt = profile?.currentBelt ?? 'white';
        final myStripes = profile?.currentStripes ?? 0;
        final myName = profile?.nickname?.isNotEmpty == true
            ? profile!.nickname!
            : (profile?.fullName ?? 'Lutador');
        await feedPostsService.like(
          giverUid: me.id,
          postId: widget.post.postId,
          authorUid: widget.post.authorUid,
          giverName: myName,
          giverBelt: myBelt,
          giverStripes: myStripes,
        );
      } else {
        await feedPostsService.unlike(
            giverUid: me.id, postId: widget.post.postId);
      }
      widget.onLikeToggled();
    } catch (_) {
      // Reverte o estado otimista em caso de erro.
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

  Future<void> _hide(BuildContext context) async {
    try {
      await feedPostsService.hide(widget.post.postId);
      widget.onHidden();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('NÃO DEI PRA OCULTAR. TENTE DE NOVO.'),
          backgroundColor: _C.blood,
        ));
      }
    }
  }

  IconData get _typeIcon {
    switch (widget.post.type) {
      case FeedPostType.graduacao:
        final gp = widget.post.payload as GraduacaoPayload;
        return gp.isBeltChange ? LucideIcons.award : LucideIcons.star;
      case FeedPostType.competicao:
        return LucideIcons.medal;
      case FeedPostType.streakMilestone:
        return LucideIcons.flame;
      case FeedPostType.sparringRecord:
        return LucideIcons.zap;
      case FeedPostType.weeklyVolume:
        return LucideIcons.activity;
      case FeedPostType.matMilestone:
        return LucideIcons.flag;
    }
  }

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
    // Reciprocidade (§2.1/P2): o autor deste post me deu oss nos últimos 14
    // dias? Falha do provider degrada p/ set vazio — o nudge só some.
    final recentLikers =
        ref.watch(myRecentLikersProvider).valueOrNull ?? const <String>{};
    final gaveMeOss =
        !widget.isMyPost && !_liked && recentLikers.contains(p.authorUid);
    final beltColor = AppTheme.getBeltColor(p.authorBelt);
    final onBelt = beltColor.computeLuminance() > 0.6 ? _C.ink : Colors.white;
    final initials = () {
      final parts = p.authorName.trim().split(RegExp(r'\s+'));
      if (parts.isEmpty || parts.first.isEmpty) return '?';
      if (parts.length == 1) return parts.first[0].toUpperCase();
      return (parts.first[0] + parts.last[0]).toUpperCase();
    }();

    return _White(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar + nome + timestamp + ícone tipo.
          Row(
            children: [
              _Avatar(
                photoUrl: p.authorPhotoUrl,
                initials: initials,
                beltColor: beltColor,
                onBelt: onBelt,
                size: 44,
                radius: 12,
                fontSize: 16,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.authorName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: _C.ink)),
                    Text(_ago(p.occurredAt),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFeatures: _C.tab,
                            color: _C.ash)),
                  ],
                ),
              ),
              Icon(_typeIcon, size: 18, color: _C.ash),
              if (widget.isMyPost) ...[
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  icon: const Icon(LucideIcons.moreVertical,
                      size: 18, color: _C.ash),
                  onSelected: (v) {
                    if (v == 'hide') _hide(context);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'hide',
                        child: Text('OCULTAR',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 13))),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Headline (usa a versão editada pelo staff, se houver).
          Text(p.displayHeadline,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: _C.ink,
                  height: 1.2)),
          // Belt swatch — visible color cue for graduation posts.
          if (p.type == FeedPostType.graduacao) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: _BeltSwatch(
                belt: (p.payload as GraduacaoPayload).belt,
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Footer: like pill. Quando o AUTOR deste post me deu oss há pouco
          // (myRecentLikersProvider) e eu ainda não retribuí, um microtexto
          // discreto convida à retribuição — kudos recíproco é o loop com a
          // evidência causal mais forte da pesquisa (§2.1/P2). O nudge some ao
          // curtir (otimista) e nunca aparece em post meu.
          Pressable(
            onTap: widget.isMyPost ? null : _toggleLike,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _liked ? Icons.favorite : Icons.favorite_border,
                  size: 16,
                  color: _liked ? _C.blood : _C.ash,
                ),
                const SizedBox(width: 5),
                Text(
                  '$_likeCount',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      fontFeatures: _C.tab,
                      color: _liked ? _C.blood : _C.ash),
                ),
                if (gaveMeOss) ...[
                  const SizedBox(width: 8),
                  const Text(
                    'te deu oss',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: _C.ash),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Linha de amigo
// =============================================================================
class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.profile, required this.onRemove});
  final FighterProfile profile;
  final VoidCallback? onRemove;

  String get _initials {
    final parts = profile.name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final beltColor = AppTheme.getBeltColor(profile.belt);
    final sport = SportId.fromString(profile.sport);
    final gradeLabel = getGradeLabel(sport, profile.belt);
    final onBelt = beltColor.computeLuminance() > 0.6 ? _C.ink : Colors.white;
    final sub = profile.academyName != null && profile.academyName!.isNotEmpty
        ? '$gradeLabel · ${profile.academyName}'
        : gradeLabel;
    return _White(
      child: Row(
        children: [
          _Avatar(
            photoUrl: profile.photoUrl,
            initials: _initials,
            beltColor: beltColor,
            onBelt: onBelt,
            size: 44,
            radius: 12,
            fontSize: 16,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: _C.ink)),
                const SizedBox(height: 2),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _C.smoke)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${profile.totalTrainings}',
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      fontFeatures: _C.tab,
                      color: _C.ink)),
              Text('TREINOS', style: _eyebrow(_C.ash, 9)),
            ],
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            IconButton(
              onPressed: onRemove,
              visualDensity: VisualDensity.compact,
              icon: const Icon(LucideIcons.x, size: 16, color: _C.ash),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Avatar: foto de rede com fallback para iniciais na cor da faixa.
// =============================================================================
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.photoUrl,
    required this.initials,
    required this.beltColor,
    required this.onBelt,
    this.size = 44,
    this.radius = 12,
    this.fontSize = 15,
  });
  final String? photoUrl;
  final String initials;
  final Color beltColor;
  final Color onBelt;
  final double size;
  final double radius;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return AppCachedImage(
        imageUrl: photoUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(radius),
        placeholder: _fallback(),
        errorIcon: _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: beltColor,
          borderRadius: BorderRadius.circular(radius),
        ),
        alignment: Alignment.center,
        child: Text(
          initials,
          style: TextStyle(
              color: onBelt,
              fontSize: fontSize,
              fontWeight: FontWeight.w900),
        ),
      );
}

// =============================================================================
// Ranking de parceiros.
// =============================================================================
class _PartnersRankCard extends StatelessWidget {
  const _PartnersRankCard({
    required this.rankAsync,
    required this.period,
  });
  final AsyncValue<List<PartnerRankEntry>> rankAsync;
  // null = GERAL; não-null = período (mensal/semanal).
  final RankingPeriod? period;

  /// Rótulo de unidade que aparece inline em cada linha do ranking.
  /// Muda com o período para deixar claro o que o número representa.
  String get _metricUnit => switch (period) {
        null => 'treinos',
        RankingPeriod.month => 'em 30d',
        RankingPeriod.week => 'em 7d',
      };

  String get _footerLabel {
    if (period == null) return 'TREINOS TOTAIS';
    return period == RankingPeriod.month
        ? 'PRESENÇAS · 30 DIAS'
        : 'PRESENÇAS · 7 DIAS';
  }

  @override
  Widget build(BuildContext context) {
    return _White(
      child: rankAsync.when(
        loading: () => const _Loading(),
        error: (_, _) => const _Voice('Ranking indisponível.'),
        data: (entries) {
          if (entries.isEmpty) {
            return const _Voice(
                'Adicione parceiros para ver o ranking aqui.');
          }
          return Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                _PartnerRankRow(
                  entry: entries[i],
                  metricUnit: _metricUnit,
                  onTap: entries[i].isMe
                      ? null
                      : () => context.push(
                          '/portal/profile/${entries[i].studentId}'),
                ),
                if (i != entries.length - 1)
                  Divider(
                      height: 14,
                      thickness: 1,
                      color: _C.ink.withValues(alpha: 0.06)),
              ],
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_footerLabel, style: _eyebrow(_C.ash, 9)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PartnerRankRow extends StatelessWidget {
  const _PartnerRankRow({
    required this.entry,
    required this.metricUnit,
    this.onTap,
  });
  final PartnerRankEntry entry;

  /// Rótulo de unidade da métrica — "treinos" (GERAL), "no mês", "na sem.".
  final String metricUnit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final beltColor = AppTheme.getBeltColor(entry.belt);
    final onBelt =
        beltColor.computeLuminance() > 0.6 ? _C.ink : Colors.white;

    final row = Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            '${entry.rank}',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                height: 1.0,
                letterSpacing: -0.5,
                fontFeatures: _C.tab,
                color: entry.isMe ? _C.blood : _C.smoke),
          ),
        ),
        const SizedBox(width: 8),
        _Avatar(
          photoUrl: entry.photoUrl,
          initials: _nameInitials(entry.name),
          beltColor: beltColor,
          onBelt: onBelt,
          size: 34,
          radius: 8,
          fontSize: 11,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            entry.name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight:
                    entry.isMe ? FontWeight.w900 : FontWeight.w700,
                letterSpacing: 0.2,
                color: _C.ink),
          ),
        ),
        const SizedBox(width: 8),
        // Ponto da faixa — cor sem texto (sem emoji).
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: beltColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Métrica + unidade (muda por período: treinos / no mês / na sem.).
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${entry.totalTrainings}',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight:
                      entry.isMe ? FontWeight.w900 : FontWeight.w800,
                  fontFeatures: _C.tab,
                  color: entry.isMe ? _C.blood : _C.ink),
            ),
            Text(
              metricUnit,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: _C.ash,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ],
    );

    return onTap != null
        ? Pressable(onTap: onTap, child: row)
        : row;
  }
}

// =============================================================================
// Base
// =============================================================================
class _White extends StatelessWidget {
  const _White({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _C.card, borderRadius: BorderRadius.circular(14)),
      child: child,
    );
    return onTap == null ? card : Pressable(onTap: onTap, child: card);
  }
}

class _Voice extends StatelessWidget {
  const _Voice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: _C.smoke, fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w600));
}

// =============================================================================
// Belt color swatch pill — graduation post cards
// =============================================================================
class _BeltSwatch extends StatelessWidget {
  const _BeltSwatch({required this.belt});
  final String belt;

  @override
  Widget build(BuildContext context) {
    final beltColor = AppTheme.getBeltColor(belt);
    final onBelt =
        beltColor.computeLuminance() > 0.6 ? _C.ink : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: beltColor,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        belt.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
          color: onBelt,
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => Column(
        children: List.generate(
          3,
          (i) => Padding(
            padding: EdgeInsets.only(bottom: i == 2 ? 0 : 14),
            child: Row(children: [
              Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                      color: _C.ink.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 12),
              Expanded(
                  child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                          color: _C.ink.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(4)))),
            ]),
          ),
        ),
      );
}
