import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../models/academy_event.dart';
import '../../providers/auth_provider.dart';
import '../../services/event_service.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/polish/polish.dart';

/// Single published Jornal post keyed by `(academyId, eventId)`.
///
/// Reads the doc directly via [EventService.getById] (one Firestore read) and
/// returns null when the post is missing or not published — the detail screen
/// is reachable only for published posts. Memoizing the fetch in a provider
/// keeps rebuilds (keyboard, theme, parent) from re-running the network call.
final eventDetailProvider = FutureProvider.family<AcademyEvent?,
    ({String academyId, String eventId})>((ref, args) async {
  final event = await EventService(args.academyId).getById(args.eventId);
  if (event == null || !event.isPublished) return null;
  return event;
});

class EventDetailScreen extends ConsumerWidget {
  final String eventId;

  const EventDetailScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final academyId = currentUser?.academyId;

    if (academyId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return _EventDetailBody(academyId: academyId, eventId: eventId);
  }
}

class _EventDetailBody extends ConsumerWidget {
  final String academyId;
  final String eventId;

  const _EventDetailBody({required this.academyId, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(
      eventDetailProvider((academyId: academyId, eventId: eventId)),
    );

    return eventAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Evento não encontrado.')),
      ),
      data: (event) {
        if (event == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Evento não encontrado.')),
          );
        }
        return _EventLoaded(event: event);
      },
    );
  }
}

class _EventLoaded extends StatelessWidget {
  final AcademyEvent event;

  const _EventLoaded({required this.event});

  String _formatDate(DateTime d, {bool withTime = true}) {
    final base = DateFormat("d 'de' MMMM yyyy", 'pt_BR').format(d);
    if (!withTime) return base;
    final time = DateFormat('HH:mm').format(d);
    return '$base às $time';
  }

  String get _dateRange {
    final start = _formatDate(event.startDate);
    if (event.endDate == null) return start;
    final same = event.startDate.day == event.endDate!.day &&
        event.startDate.month == event.endDate!.month;
    if (same) {
      return '${_formatDate(event.startDate)} até ${DateFormat('HH:mm').format(event.endDate!)}';
    }
    return '$start até ${_formatDate(event.endDate!)}';
  }

  Future<void> _openCta(BuildContext context) async {
    final url = event.ctaUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o link.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          // Hero image + back button
          SliverAppBar(
            expandedHeight: event.coverUrl != null ? 240 : 120,
            pinned: true,
            backgroundColor: AppTheme.surface,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              background: event.coverUrl != null
                  ? Hero(
                      tag: 'event-cover-${event.id}',
                      child: AppCachedImage(
                        imageUrl: event.coverUrl!,
                        width: double.infinity,
                        height: 240,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Container(color: AppTheme.surfaceVariant),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Post-type pill (Evento / Notícia / Seminário) so news and
                  // seminars are visually distinct from events on this shared
                  // detail screen. Same colours as the jornal feed badge.
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _PostTypePill(type: event.postType),
                        // "Acontecendo agora" only makes sense for real events;
                        // news/seminar posts often start "now" with no endDate,
                        // which would spuriously read as ongoing.
                        if (event.postType == PostType.event && event.isOngoing)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.successLight,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Acontecendo agora',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.success,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Title
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.5,
                      height: 1.2,
                    ),
                  ).fadeInQuick(),
                  const SizedBox(height: 16),

                  // Date
                  _InfoRow(
                    icon: LucideIcons.calendar,
                    text: _dateRange,
                  ),

                  // Location
                  if (event.location != null && event.location!.isNotEmpty)
                    _InfoRow(
                      icon: LucideIcons.mapPin,
                      text: event.location!,
                    ),

                  const SizedBox(height: 24),

                  // Description
                  if (event.description.isNotEmpty) ...[
                    const Divider(),
                    const SizedBox(height: 16),
                    Text(
                      event.description,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppTheme.textSecondary,
                        height: 1.6,
                      ),
                    ),
                  ],

                  // CTA
                  if (event.ctaUrl != null && event.ctaUrl!.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => _openCta(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.textPrimary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          event.ctaLabel?.isNotEmpty == true
                              ? event.ctaLabel!
                              : 'Saiba mais',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Coloured pill describing the post type: Evento=blue, Notícia=grey,
/// Seminário=purple (mirrors the jornal feed `_PostTypeBadge` colours).
class _PostTypePill extends StatelessWidget {
  final PostType type;
  const _PostTypePill({required this.type});

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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
