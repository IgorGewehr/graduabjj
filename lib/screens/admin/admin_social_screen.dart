import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/brand_tokens.dart';
import '../../core/theme.dart';
import '../../models/feed_post.dart';
import '../../providers/friend_providers.dart';
import '../../services/feed_posts_service.dart';
import '../../widgets/cached_image.dart';
import '../portal/ranking_screen.dart';

/// SOCIAL (admin/professor) — substitui o antigo item "Ranking" do menu.
///
/// Duas abas:
///  - RANKING: o mesmo leaderboard dos alunos (RankingScreen embutido, forStaff).
///  - ATIVIDADE: TODA a atividade da academia (o mesmo feed que os alunos veem
///    na Galera), com poder de MODERAÇÃO — ocultar/reexibir ou editar o texto de
///    qualquer post. A moderação reflete para todos os alunos.
class AdminSocialScreen extends StatefulWidget {
  const AdminSocialScreen({super.key});

  @override
  State<AdminSocialScreen> createState() => _AdminSocialScreenState();
}

class _AdminSocialScreenState extends State<AdminSocialScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.bone,
      appBar: AppBar(
        title: const Text('Social'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppTheme.primary,
          unselectedLabelColor: Brand.ash,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
          tabs: const [
            Tab(text: 'RANKING'),
            Tab(text: 'ATIVIDADE'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          RankingScreen(forStaff: true, embedded: true),
          _ModerationFeed(),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Aba ATIVIDADE — feed da academia com moderação
// ════════════════════════════════════════════════════════════════════════════

class _ModerationFeed extends ConsumerWidget {
  const _ModerationFeed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(staffAcademyFeedProvider);

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: () async {
        HapticFeedback.mediumImpact();
        ref.invalidate(staffAcademyFeedProvider);
        await ref.read(staffAcademyFeedProvider.future);
      },
      child: feedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            _Empty(
              icon: LucideIcons.alertCircle,
              message: 'Não deu pra carregar a atividade.\nPuxe para atualizar.',
            ),
          ],
        ),
        data: (posts) {
          if (posts.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                _Empty(
                  icon: LucideIcons.activity,
                  message:
                      'Nenhuma atividade ainda.\nGraduações, competições e treinos\ndos seus alunos aparecem aqui.',
                ),
              ],
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: posts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _ModPostCard(post: posts[i]),
          );
        },
      ),
    );
  }
}

class _ModPostCard extends ConsumerStatefulWidget {
  const _ModPostCard({required this.post});
  final FeedPost post;

  @override
  ConsumerState<_ModPostCard> createState() => _ModPostCardState();
}

class _ModPostCardState extends ConsumerState<_ModPostCard> {
  bool _busy = false;

  Future<void> _toggleHidden() async {
    if (_busy) return;
    setState(() => _busy = true);
    final hide = !widget.post.hiddenByStaff;
    try {
      await feedPostsService.staffSetHidden(widget.post.postId, hide);
      ref.invalidate(staffAcademyFeedProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(hide ? 'POST OCULTADO PARA A ACADEMIA' : 'POST REEXIBIDO'),
          backgroundColor: Brand.ink,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('NÃO DEU. TENTE DE NOVO.'),
          backgroundColor: Brand.blood,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editHeadline() async {
    final controller =
        TextEditingController(text: widget.post.displayHeadline);
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Editar texto',
            style: TextStyle(fontWeight: FontWeight.w900)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: 'Texto exibido do post',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR',
                style: TextStyle(color: Brand.ash, fontWeight: FontWeight.w800)),
          ),
          if (widget.post.staffHeadline != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, '__reset__'),
              child: const Text('RESTAURAR ORIGINAL',
                  style:
                      TextStyle(color: Brand.blood, fontWeight: FontWeight.w800)),
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('SALVAR',
                style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      // '__reset__' → limpa a sobrescrita (volta à headline determinística).
      await feedPostsService.staffSetHeadline(
          widget.post.postId, result == '__reset__' ? null : result);
      ref.invalidate(staffAcademyFeedProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('NÃO DEU PRA EDITAR.'),
          backgroundColor: Brand.blood,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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

  IconData get _typeIcon {
    switch (widget.post.type) {
      case FeedPostType.graduacao:
        return LucideIcons.award;
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

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final hidden = p.hiddenByStaff;
    final beltColor = AppTheme.getBeltColor(p.authorBelt);
    final onBelt = beltColor.computeLuminance() > 0.6 ? Brand.ink : Colors.white;
    final initials = () {
      final parts = p.authorName.trim().split(RegExp(r'\s+'));
      if (parts.isEmpty || parts.first.isEmpty) return '?';
      if (parts.length == 1) return parts.first[0].toUpperCase();
      return (parts.first[0] + parts.last[0]).toUpperCase();
    }();

    return Opacity(
      opacity: hidden ? 0.55 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: hidden
              ? Border.all(color: Brand.blood.withValues(alpha: 0.4), width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Avatar(
                  photoUrl: p.authorPhotoUrl,
                  initials: initials,
                  beltColor: beltColor,
                  onBelt: onBelt,
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
                              color: Brand.ink)),
                      Text(_ago(p.occurredAt),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Brand.ash)),
                    ],
                  ),
                ),
                Icon(_typeIcon, size: 18, color: Brand.ash),
                const SizedBox(width: 2),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  PopupMenuButton<String>(
                    icon: const Icon(LucideIcons.moreVertical,
                        size: 18, color: Brand.ash),
                    onSelected: (v) {
                      if (v == 'hide') _toggleHidden();
                      if (v == 'edit') _editHeadline();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'hide',
                        child: Text(hidden ? 'REEXIBIR' : 'OCULTAR',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('EDITAR TEXTO',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(p.displayHeadline,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Brand.ink,
                    height: 1.2)),
            const SizedBox(height: 12),
            Row(
              children: [
                if (hidden) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Brand.blood.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('OCULTO',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Brand.blood,
                            letterSpacing: 0.5)),
                  ),
                  const SizedBox(width: 10),
                ],
                if (p.staffHeadline != null) ...[
                  const Icon(LucideIcons.pencil, size: 12, color: Brand.ash),
                  const SizedBox(width: 4),
                  const Text('EDITADO',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Brand.ash,
                          letterSpacing: 0.5)),
                  const SizedBox(width: 10),
                ],
                const Spacer(),
                Icon(Icons.favorite, size: 14, color: Brand.ash.withValues(alpha: 0.7)),
                const SizedBox(width: 4),
                Text('${p.likeCount}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Brand.ash)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.photoUrl,
    required this.initials,
    required this.beltColor,
    required this.onBelt,
  });

  final String? photoUrl;
  final String initials;
  final Color beltColor;
  final Color onBelt;

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AppCachedImage(
          imageUrl: photoUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: beltColor,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(initials,
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w900, color: onBelt)),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 44, color: const Color(0xFFC9C5BC)),
        const SizedBox(height: 16),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.4,
                color: Color(0xFF9A968C))),
      ],
    );
  }
}
