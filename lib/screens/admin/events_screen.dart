import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/academy_event.dart';
import '../../providers/auth_provider.dart';
import '../../providers/portal_providers.dart';
import '../../services/event_service.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/polish/polish.dart';

/// Admin management UI for the academy "Jornal" (events / news / seminars).
///
/// Two tabs split the full post list (newest-first from
/// [journalAllProvider]) into Published and Drafts. Rows offer edit / delete,
/// and drafts additionally offer a one-tap Publish.
class AdminEventsScreen extends ConsumerStatefulWidget {
  const AdminEventsScreen({super.key});

  @override
  ConsumerState<AdminEventsScreen> createState() => _AdminEventsScreenState();
}

class _AdminEventsScreenState extends ConsumerState<AdminEventsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  EventService? _service() {
    final academyId = ref.read(currentUserProvider).valueOrNull?.academyId;
    if (academyId == null) return null;
    return EventService(academyId);
  }

  Future<void> _delete(AcademyEvent event) async {
    final confirmed = await FeedbackUtils.showDeleteConfirmDialog(
      context,
      itemName: 'publicação',
      customMessage:
          '"${event.title}" será removida permanentemente. Esta ação não '
          'pode ser desfeita.',
    );
    if (!confirmed) return;
    final service = _service();
    if (service == null) return;
    try {
      await service.delete(event.id);
      if (!mounted) return;
      ref.invalidate(journalAllProvider);
      context.showSuccess('Publicação excluída.');
    } catch (e) {
      if (mounted) context.showError('Não foi possível excluir: $e');
    }
  }

  Future<void> _publish(AcademyEvent event) async {
    final service = _service();
    if (service == null) return;
    try {
      await service.publish(event.id);
      if (!mounted) return;
      ref.invalidate(journalAllProvider);
      context.showSuccess('Publicação no ar!');
    } catch (e) {
      if (mounted) context.showError('Não foi possível publicar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(journalAllProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        title: const Text('Jornal da Academia'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(text: 'Publicados'),
            Tab(text: 'Rascunhos'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        onPressed: () => context.push('/admin/jornal/novo'),
        icon: const Icon(LucideIcons.plus),
        label: const Text('Nova publicação'),
      ),
      body: async.when(
        data: (events) {
          final published = events.where((e) => e.isPublished).toList();
          final drafts = events.where((e) => !e.isPublished).toList();
          return TabBarView(
            controller: _tabController,
            children: [
              _buildList(published, isDraft: false),
              _buildList(drafts, isDraft: true),
            ],
          );
        },
        loading: () => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: PolishSkeleton.list(count: 4, itemHeight: 120),
        ),
        error: (e, _) => _ErrorState(
          message: 'Não foi possível carregar o jornal.',
          onRetry: () => ref.invalidate(journalAllProvider),
        ),
      ),
    );
  }

  Widget _buildList(List<AcademyEvent> items, {required bool isDraft}) {
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(journalAllProvider),
      child: items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.18),
                _EmptyState(
                  icon: isDraft
                      ? LucideIcons.fileEdit
                      : LucideIcons.newspaper,
                  title: isDraft
                      ? 'Nenhum rascunho'
                      : 'Nenhuma publicação no ar',
                  subtitle: isDraft
                      ? 'Crie uma publicação e salve sem publicar para vê-la aqui.'
                      : 'Toque em "Nova publicação" para começar.',
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _PostRow(
                event: items[i],
                showPublish: isDraft,
                onEdit: () =>
                    context.push('/admin/jornal/${items[i].id}/editar'),
                onDelete: () => _delete(items[i]),
                onPublish: () => _publish(items[i]),
              ).entrance(index: i),
            ),
    );
  }
}

/// A single Jornal post row in the admin list.
class _PostRow extends StatelessWidget {
  final AcademyEvent event;
  final bool showPublish;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPublish;

  const _PostRow({
    required this.event,
    required this.showPublish,
    required this.onEdit,
    required this.onDelete,
    required this.onPublish,
  });

  static String _formatDate(DateTime d) =>
      DateFormat("d 'de' MMM 'de' y", 'pt_BR').format(d);

  @override
  Widget build(BuildContext context) {
    final hasCover = event.coverUrl != null && event.coverUrl!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: hasCover
                      ? AppCachedImage(
                          imageUrl: event.coverUrl!,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 72,
                          height: 72,
                          color: AppTheme.surfaceVariant,
                          alignment: Alignment.center,
                          child: Text(
                            event.postType.emoji,
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PostTypeBadge(type: event.postType),
                      const SizedBox(height: 6),
                      Text(
                        event.title,
                        style: const TextStyle(
                          fontSize: 15,
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
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20, color: AppTheme.divider),
            Row(
              children: [
                if (showPublish) ...[
                  _RowAction(
                    icon: LucideIcons.send,
                    label: 'Publicar',
                    color: AppTheme.success,
                    onTap: onPublish,
                  ),
                  const SizedBox(width: 4),
                ],
                _RowAction(
                  icon: LucideIcons.edit3,
                  label: 'Editar',
                  color: AppTheme.textPrimary,
                  onTap: onEdit,
                ),
                const Spacer(),
                _RowAction(
                  icon: LucideIcons.trash2,
                  label: 'Excluir',
                  color: AppTheme.error,
                  onTap: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RowAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _RowAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Coloured pill describing the post type: Evento=blue, Notícia=grey,
/// Seminário=purple.
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

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppTheme.textDisabled),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.alertCircle,
              size: 48, color: AppTheme.textDisabled),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Tentar novamente')),
        ],
      ),
    );
  }
}
