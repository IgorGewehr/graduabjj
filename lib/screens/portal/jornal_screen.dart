import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../models/academy_event.dart';
import '../../providers/portal_providers.dart';
import '../../widgets/cached_image.dart';

/// Student-facing "Jornal da Academia" feed: every published post
/// (events, news, seminars), newest-first, each tappable to its detail.
class JornalScreen extends ConsumerWidget {
  const JornalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(journalEventsProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Jornal da Academia'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(journalEventsProvider),
        child: postsAsync.when(
          data: (posts) {
            if (posts.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  _JornalEmptyState(),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: posts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final post = posts[i];
                return _JornalCard(
                  event: post,
                  onTap: () => context.push('/portal/eventos/${post.id}'),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 120),
              _JornalErrorState(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Post card mirroring the home `_EventCard` visual language, plus a
/// [_PostTypeBadge] describing the post type.
class _JornalCard extends StatelessWidget {
  final AcademyEvent event;
  final VoidCallback onTap;

  const _JornalCard({required this.event, required this.onTap});

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(d.year, d.month, d.day);
    final diff = eventDay.difference(today).inDays;

    if (diff == 0) return 'Hoje, ${DateFormat('HH:mm').format(d)}';
    if (diff == 1) return 'Amanhã, ${DateFormat('HH:mm').format(d)}';
    if (diff == -1) return 'Ontem, ${DateFormat('HH:mm').format(d)}';
    if (diff > 0 && diff < 7) {
      return DateFormat("EEEE, HH:mm", 'pt_BR').format(d);
    }
    return DateFormat("d 'de' MMM", 'pt_BR').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final hasCover = event.coverUrl != null && event.coverUrl!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            // Cover thumbnail
            ClipRRect(
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(13)),
              child: hasCover
                  ? AppCachedImage(
                      imageUrl: event.coverUrl!,
                      width: 88,
                      height: 80,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 88,
                      height: 80,
                      color: AppTheme.border,
                      child: const Icon(
                        LucideIcons.newspaper,
                        size: 28,
                        color: AppTheme.textDisabled,
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PostTypeBadge(type: event.postType),
                    const SizedBox(height: 4),
                    Text(
                      event.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(event.startDate),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    if (event.location != null && event.location!.isNotEmpty)
                      Text(
                        event.location!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textDisabled,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(LucideIcons.chevronRight,
                  size: 16, color: AppTheme.textDisabled),
            ),
          ],
        ),
      ),
    );
  }
}

/// Coloured pill describing the post type: Evento=blue, Notícia=grey,
/// Seminário=purple (mirrors the admin events screen / A6 colors).
class _PostTypeBadge extends StatelessWidget {
  final PostType type;
  const _PostTypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color color;
    switch (type) {
      case PostType.event:
        label = 'Evento';
        color = AppTheme.info;
        break;
      case PostType.news:
        label = 'Notícia';
        color = AppTheme.textSecondary;
        break;
      case PostType.seminar:
        label = 'Seminário';
        color = const Color(0xFF8B5CF6);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _JornalEmptyState extends StatelessWidget {
  const _JornalEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(LucideIcons.newspaper, size: 48, color: AppTheme.textDisabled),
            SizedBox(height: 16),
            Text(
              'Nenhuma postagem ainda',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _JornalErrorState extends StatelessWidget {
  const _JornalErrorState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(LucideIcons.alertCircle,
                size: 48, color: AppTheme.textDisabled),
            SizedBox(height: 16),
            Text(
              'Não foi possível carregar o jornal.\nPuxe para atualizar.',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
